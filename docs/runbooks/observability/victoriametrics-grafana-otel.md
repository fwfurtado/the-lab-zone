---
tipo: runbook
componente: observability
tags: [victoriametrics, vmagent, vmoperator, grafana, otel-collector, vmservicescrape, webhook-cert, reconciliacao, victorialogs, filelog, severity, logsql, stanza]
fases: [5, 6, 7]
relacionado: [runbooks/cilium-rede, runbooks/argo-workflows]
---

# VictoriaMetrics, Grafana e OTel Collector

Incidentes da stack de observabilidade. O padrão dominante: **VM operator não materializa
recurso novo → restart** (aconteceu ≥3x; ver no fim).

## CRDs bloqueados pelo AppProject

**Sintoma:** ArgoCD recusa sync com `resource ... is not permitted in project`.
**Causa:** `clusterResourceWhitelist` não incluía `CustomResourceDefinition` nem os CRDs do
operator VictoriaMetrics (`operator.victoriametrics.com/*`).
**Fix:** expandir `clusterResourceWhitelist` no `projects/observability.yaml`.

## node-exporter FailedCreate por PodSecurity

**Sintoma:** pods do node-exporter `Pending`/`FailedCreate` com erro de PodSecurity admission.
**Causa:** o namespace `observability` com policy `baseline` bloqueia `hostNetwork`/`hostPID`/
`hostPath` que o node-exporter exige.
**Fix:** labels `pod-security.kubernetes.io/{enforce,audit,warn}: privileged` no `namespace.yaml`.

## VMAlert falha no `helm template` sem notifier

**Sintoma:** `helm template` falha com `Neither notifier, notifiers nor notifierConfigRef is
set for vmalert`.
**Causa:** o chart `victoria-metrics-k8s-stack` valida em template time que o VMAlert tem ao
menos um notifier; com `alertmanager.enabled: false` o deploy falha por inteiro.
**Fix:** `alertmanager.enabled: true` — o Alertmanager interno vira o notifier padrão.

## VictoriaLogs Headless (sem ClusterIP)

**Sintoma:** `victoria-logs-vls-server` com `ClusterIP: None`; OTel não resolve o endpoint.
**Causa:** o chart `victoria-logs-single` defaulta `clusterIP: None`. A key `service.clusterIP`
na **raiz** do values é ignorada — a correta é `server.service.clusterIP`.
**Fix:** `server.service.clusterIP: ""` (string vazia → K8s atribui ClusterIP normal).
**Atenção:** mudar `clusterIP` é imutável — `kubectl delete svc victoria-logs-vls-server`; o
ArgoCD recria no próximo sync.

## Grafana Deployment OutOfSync após mudança de strategy

(Mesma classe de "strategy imutável" do `runbooks/gitops-argocd/`.) Deployment com PVC RWO
deve nascer com `deploymentStrategy.type: Recreate` + `rollingUpdate: null`. Mudar depois exige
`kubectl delete deployment grafana` + terminate + sync com prune.

## Grafana datasource com DNS errado (nameOverride)

**Sintoma:** datasources VM/VLogs falham em Test com "connection refused"/"no such host".
**Causa:** service names gerados com `nameOverride: vmks` diferem dos nomes sem override; só são
conhecidos após o primeiro deploy.
**Fix:** usar os service names reais (ex. `vmsingle-victoria-metrics-vmks:8428`,
`victoria-logs-vls-server:9428`) nos FQDNs do datasource.

## Grafana dashboard via ConfigMap: datasource não resolvido

**Sintoma:** dashboard importado por ConfigMap com dropdown "Datasource" vazio.
**Causa:** o mecanismo `__inputs`/`${DS_VICTORIAMETRICS}` é pra import manual; via ConfigMap a
variável não resolve.
**Fix:** substituir `${DS_VICTORIAMETRICS}` pelo UID real do datasource direto no JSON. (O
sidecar `grafana-sc-dashboard` importa qualquer ConfigMap com label `grafana_dashboard: "1"`.)

## OTel Collector — `image.repository` obrigatório (chart ≥ 0.127.x)

**Sintoma:** `[ERROR] 'image.repository' must be set`.
**Causa:** breaking change — o chart parou de ter default por suportar múltiplas distribuições.
**Fix:** declarar `image.repository: .../opentelemetry-collector-k8s` + `command.name: otelcol-k8s`.

## OTel Collector — `prometheusremotewrite` indisponível no `otelcol-k8s`

**Sintoma:** CrashLoopBackOff com `unknown type: "prometheusremotewrite"`.
**Causa:** `otelcol-k8s` é distribuição slim sem esse exporter (só `otlp`, `otlphttp`, `debug`,
`file`, `loadbalancing`, `otelarrow`).
**Fix:** trocar pra `otlphttp` apontando pro endpoint OTLP nativo do VMSingle
(`http://vmsingle-...:8428/opentelemetry`). VMSingle aceita OTLP em `/opentelemetry`.

## kube-controller-manager/scheduler/etcd: ver runbook do Talos

Targets DOWN do control plane (bind-address 127.0.0.1, TLS só p/ localhost, etcd sem listener)
estão em `runbooks/talos/control-plane-etcd-gpu-taints.md` — é causa de machine config, não da
stack VM.

## Webhook cert do VM Operator em churn sob ArgoCD

**Sintoma:** bursts (~a cada sync) de `tls: bad certificate` nos logs do operator (de IPs dos
CIDRs de pod dos CPs), cada burst seguido de `certwatcher Updated current TLS certificate`. Em
paralelo, `MountVolume.SetUp failed ... secret "...-validation" not found` + restarts.
**Causa:** o cert do webhook era **Helm-generated** (usa `lookup` do Helm pra reusar o cert). O
ArgoCD renderiza com `helm template` e **não respeita `lookup`** — a cada sync gera cert +
caBundle novos. Com `prune: true`, o secret é recriado, abrindo janela de `FailedMount` →
restart → reabre a janela de `bad certificate`. Loop auto-sustentado.
**Fix:** migrar pro cert-manager: `admissionWebhooks.certManager.enabled: true` no
`victoria-metrics-operator`. E `ignoreDifferences` no `caBundle` que o cainjector injeta (senão
o app pisca OutOfSync):
```yaml
ignoreDifferences:
  - group: admissionregistration.k8s.io
    kind: ValidatingWebhookConfiguration
    jqPathExpressions: ['.webhooks[]?.clientConfig.caBundle']
```
**Validação:** o secret `...-validation` ficar **sem** o label `app.kubernetes.io/instance`
garante que o ArgoCD não o reivindica nem pruna (cert-manager é o dono).
**Lição:** k8s-stack via ArgoCD **sem** cert-manager churna o cert do webhook (`lookup` não
respeitado). Com cert-manager no cluster, `certManager.enabled: true` elimina o loop — e dá o
fix **permanente** pro restart-paliativo do incidente abaixo.

## VMPodScrape/VMServiceScrape/VMRule não materializa → RESTART do operator

**Sintoma:** recurso do VM operator criado e correto (`operational`/`VALID`), selectors casam,
`selectAllByDefault: true`, sem erro — mas não vira target/rulefile/config. Visto com:
VMPodScrape após TLS mismatch (fase 6), scrape novo (fase 7), scrape+rule+config de drops (fase 9).
**Causa:** o operator não reconcilia o recurso novo até ser reiniciado.
**Fix:** `kubectl -n observability rollout restart deploy/victoria-metrics-victoria-metrics-operator`
(ou o vmagent, se o scrape novo não aparece nos `activeTargets` — `rollout restart
deploy/vmagent-...`, fase 7).
**Lição:** **aconteceu ≥3x.** Recurso VM correto que "não aparece" → primeiro reflexo é
reiniciar o operator (ou o vmagent), não o último recurso. Causas estruturais que ALÉM disso
quebram o target: selectors errados (labels reais via `--show-labels`), `matchExpressions`
(usar só `matchLabels` — ver `runbooks/backup-dr/`), scrape cross-namespace sem
`namespaceSelector` (ver `runbooks/argo-workflows/`).

## Dashboards congelados: uid duplicado revoga a escrita de TODOS os providers

**Sintoma:** dashboards do repo param de refletir o Git. Nenhum erro na UI, ArgoCD `Synced`,
ConfigMap correto no cluster. No log do Grafana, a cada 30s:
`the same UID is used more than once  uid=rYdddlPWk times=2 providers="[default sidecarProvider]"`
seguido de `dashboards provisioning provider has no database write permissions because of duplicates`.

**Causa:** o mesmo dashboard vinha de dois provedores — `dashboards.default.node-exporter`
(gnetId 1860, "Node Exporter Full", uid `rYdddlPWk`) no values do chart, e o ConfigMap que o
`victoria-metrics-k8s-stack` entrega via sidecar. Detectada a colisão de uid, o Grafana **revoga
a permissão de escrita de AMBOS os providers** — não só do duplicado. Efeito: *nenhum* dashboard
é gravado, e o Grafana segue servindo a versão antiga sem sinal na UI.

**Causa raiz (a que importa):** dashboards por `gnetId` **não** são ConfigMap. Um init container
(`download-dashboards`) baixa do grafana.com para `/var/lib/grafana/dashboards/default` — dentro
do **PVC**. O script só ESCREVE, nunca apaga. Remover a entrada do `values.yaml` impede o
download futuro, mas o `.json` órfão permanece no disco e o provider `default` continua
carregando. Estado fora do ciclo de vida do reconciliador; `prune` do Argo não enxerga.

**Diagnóstico:**
1. `kubectl -n observability logs deploy/grafana -c grafana | grep -iE 'used more than once|write permissions'`
2. Um duplicado é suficiente para congelar todos. `providers="[default sidecarProvider]"` diz de
   onde vêm as duas cópias.
3. Provar o congelamento (a UI não acusa): `scripts/check-dashboards-drift.sh` compara cada
   ConfigMap do repo com `/api/dashboards/uid/<uid>`.
4. O que está no disco: `kubectl -n observability exec deploy/grafana -c grafana -- ls /var/lib/grafana/dashboards/default`

**Fix:** remover o duplicado do values **não basta** — o arquivo fica no PVC. Fim de linha:
`dashboards:` e `dashboardProviders:` saem do values (sem eles, sem init container e sem provider
`default` lendo o disco), e **todo** dashboard vira ConfigMap versionado com label
`grafana_dashboard: "1"`, servido pelo sidecar. Gerar/atualizar com
`./scripts/gnet-to-configmap.py --gnet-id <id> --revision <r> --name <slug>`, que troca os
`${DS_*}` pela variável `${ds}` (imune a troca de uid de datasource) e injeta a var no topo.
Limpeza do resíduo: `rm -rf /var/lib/grafana/dashboards/default` + rollout restart.
Ao remover o provider `default`, o Grafana apaga do banco os dashboards que ele havia criado —
não sobra órfão. `persistence` **continua ligada**: o sqlite guarda histórico do Explore,
anotações e preferências, e nunca causou drift.

**Lição:** `gnetId` no chart do Grafana é **estado no PVC disfarçado de config**. Um único uid
duplicado não degrada só o dashboard colidente — ele desliga a escrita de todos, silenciosamente.
Mesma assinatura do usuário `analytics` criado por SQL no ClickHouse (ver `runbooks/argo-workflows/`):
estado que vive fora do reconciliador diverge do Git sem ninguém perceber.

## Grafana em CrashLoop ao fixar `uid` de datasource já existente

**Sintoma:** após declarar `uid` explícito em datasources que já existiam, o pod entra em
CrashLoopBackOff. No log: `Failed to provision data sources` /
`Datasource provisioning error: data source not found`, e o processo morre em
`starting module provisioning`.

**Causa:** o provisionamento casa a datasource pelo **nome**, mas ao encontrar `uid` diferente do
que está no banco tenta resolvê-la pelo uid novo — que não existe. Como `provisioning` é módulo de
boot, a falha derruba o processo. Sem `uid` explícito o Grafana gera um aleatório (`P4169E866C3094E38`),
que acaba hardcoded em dashboards exportados — valor crítico que não está no Git.

**Diagnóstico:** `kubectl -n observability logs deploy/grafana -c grafana | grep -i provision`.
UIDs atuais: `curl -s -u admin:$PW $GRAFANA_URL/api/datasources | jq '.[] | {name, uid}'`.

**Fix:** declarar `deleteDatasources` (nome + `orgId`) para cada datasource cujo uid muda. O
Grafana apaga as listadas **antes** de inserir/atualizar, recriando cada uma já com o uid
definitivo. É idempotente. **Pré-requisito:** nenhum dashboard pode referenciar o uid antigo —
migrar as refs para uma variável `${ds}` do tipo `datasource` (ver `configmap-*-dashboard.yaml`).

**Armadilha pós-fix:** com os uids novos no banco, a UI ainda erra ("nenhum datasource abre",
Explore vazio) porque o **navegador** guarda o datasource por uid no `localStorage`. Aba anônima
resolve. Antes de investigar o backend, prove-o server-side:
`curl -s -u admin:$PW $GRAFANA_URL/api/datasources/uid/victoriametrics/health`.

**Lição:** uid de datasource é chave estrangeira de dashboards e correlações. Deixá-lo implícito
transfere um identificador crítico para fora do Git; mudá-lo depois exige `deleteDatasources`, e
o custo cresce com cada referência criada nesse meio-tempo. Fixe cedo.

## Alerta de agente firing sem incidente: span de erro ≠ falha de sistema

**Sintoma:** `AgentSpanErrors` (grupo `agents-red`) em `Firing` contínuo, para `service_name`
como `qa-bot` e `litellm`, sem nenhuma reclamação de que os agentes estejam quebrados. O gráfico
do alerta mostra taxa de erro > 0 e subindo.

**Causa:** a regra era `sum by (service_name) (rate(agents_span_metrics_calls{status_code="STATUS_CODE_ERROR"}[15m])) > 0`
— dispara com **qualquer** span em erro. Num agente, erro em nó-folha é rotina, não incidente:
um `tools/call` para um pod sem log, um recurso vazio, ou o 429 do LiteLLM que **cai no fallback**
(a tentativa que falhou marca `STATUS_CODE_ERROR` mesmo quando a request final teve sucesso). O
alerta contava ruído de recuperação como fogo.

**Diagnóstico — a query que separa ruído de falha real:** comparar erro interno com erro de raiz.

```promql
# tudo que o alerta grosseiro conta
sum(rate(agents_span_metrics_calls{service_name="qa-bot", status_code="STATUS_CODE_ERROR"}[15m]))
# só o span RAIZ (a interação que de fato falhou p/ o usuário)
sum(rate(agents_span_metrics_calls{service_name="qa-bot", span_name="invoke_agent agent", status_code="STATUS_CODE_ERROR"}[15m]))
```

Medido: interno `0.18/s`, raiz `0/s` → nenhuma interação falhou. `count by (span_name)` localiza
onde os erros vivem (`execute_tool`/`tools/call` de `kubernetes_pods_log`, `kubernetes_resources_list`
— o agente sondando o cluster). No Tempo, `{resource.service.name="qa-bot" && status=error}` volta
vazio: o `status=error` do trace olha a raiz, que está verde.

**Fix:** dois sinais alinhados à realidade, no lugar do `> 0` bruto:
- `AgentInteractionErrors` — só o span raiz (`span_name="invoke_agent agent"`) em erro. É a falha
  que importa: a interação quebrou. Fica quieto quando as raízes estão verdes.
- `AgentToolErrorRatioHigh` — razão de tool calls em erro (`execute_tool|tools/call`) acima de um
  piso alto (30%). Ignora o pod-sem-log isolado, pega degradação sistêmica (MCP fora, RBAC negando).

O `TriageErrorRatioHigh` já seguia esse princípio (filtra `span_name="triage"`, razão > 20%) — foi
o modelo. **Calibração:** o piso de 30% é chute educado; rode a razão real por alguns dias e ajuste.

**Lição:** span de erro ≠ falha de sistema. Em agente, erro em folha é frequentemente recuperação
em ação — inclusive o próprio fallback do LiteLLM. Alerta sobre agente olha a **raiz** (a interação)
ou **razões** (saúde agregada), quase nunca a contagem bruta de spans. `> 0` num span-metric de
agente é quase sempre calibração errada.

## VictoriaLogs: tudo `unknown`, impossível filtrar por nível

**Sintoma:** todo log no datasource VictoriaLogs cai em `unknown`; o histograma
"Logs volume" é 100% cinza e só resta grep no `_msg` — nenhum filtro por nível
funciona.
**Causa:** o preset `logsCollection` injeta um `filelog` cujo único operator é
`container` (unwrap CRI). O payload da app fica cru em `body`, então o
`SeverityText` do OTLP **nunca é setado**. Na ingestão, o VLS materializa
`severity_text="Unspecified"` (nunca vazio), e o plugin do Grafana — que resolve
nível procurando `severity_text` — pinta `unknown`.
**Diagnóstico:** `_time:15m * | stats by (severity_text) count() as n` mostra
`Unspecified` dominando. Prova de que não é "log sem campo": `NOT severity_text:*`
retorna **zero** — o campo está presente em 100% dos logs. O problema é valor
não-mapeável, não ausência de campo.
**Fix:** parsear no `filelog` e setar severidade explícita por formato (router +
`severity_parser` por ramo) — ver ADR-0019. **Regra: `noop` == `Unspecified` ==
`unknown`.** Todo formato que se quer classificar PRECISA passar por um
`severity_parser`; não existe nível default implícito.
**Lição:** ausência de severidade OTLP não é neutra — o VLS a materializa como
`Unspecified`, que o Grafana lê como `unknown`. É contraintuitivo e volta a
morder: o balde `unknown` grande quase sempre é severidade não-setada, não log
"sem nível".

## OTel Collector CrashLoop: `unsupported type` no filelog

**Sintoma:** collector em CrashLoopBackOff após editar os operators do filelog.
Log: `failed to get config: … 'receivers' error reading configuration for
"filelog": … 'operators[N]' unsupported type 'logfmt_parser'`.
**Causa:** `logfmt_parser` **não existe** no stanza. Parsers válidos:
`json_parser`, `regex_parser`, `csv_parser`, `key_value_parser`,
`severity_parser`, `time_parser`, `uri_parser`, `container`, `router`, `move`,
`add`, `copy`, `noop`. Um tipo inválido faz o collector **recusar o config
inteiro no boot** — não degrada só aquele operator.
**Diagnóstico:** `kubectl -n observability logs
ds/otel-collector-opentelemetry-collector-agent | grep -iE "unsupported|error"`.
O índice `operators[N]` (0-based) aponta o operator ofensor.
**Fix:** logfmt no filelog é `regex_parser` (só o nível:
`(?:^|\s)level=(?P<level>\w+)`) — o `key_value_parser` quebra valor citado com
espaço (`msg="a b c"` → 3 pares). Validar antes do merge:
`otelcol-k8s validate --config <render do helm template>`.
**Lição:** tipo de operator inválido = config recusado no boot inteiro
(CrashLoop), não falha localizada naquele ramo. Vale um `otelcol validate` no
CI antes de qualquer merge que toque o filelog.

## LogsQL: filtro por label "não filtra" (casa tudo, em silêncio)

**Sintoma:** `k8s_namespace_name:!="tetragon"` não exclui nada — o namespace
segue aparecendo e o `unknown` não cai. Nenhum erro.
**Causa:** o campo real é `k8s.namespace.name` (com **pontos** — o VLS preserva
o nome semconv do OTLP), não `k8s_namespace_name` (underscore, convenção do
vlagent). O campo com underscore **não existe**; e no LogsQL,
`campo_inexistente:!="x"` casa **tudo** (o campo ausente tem valor vazio,
`"" != "x"` é sempre verdadeiro → filtro vira no-op).
**Diagnóstico:** conferir os nomes reais no painel Fields do Explore, ou
`curl .../select/logsql/field_names -d 'query=_time:1h' | jq -r '.values[].value'`.
**Fix:** nome real com aspas (por causa dos pontos):
`"k8s.namespace.name":!="tetragon"`. **Padrão do setup: tudo é dot-notation**
(`k8s.pod.name`, `container.image.tag`), nunca underscore.
**Lição:** filtro que "não faz nada" → desconfie primeiro do nome do campo.
`campo_inexistente:!=x` falha em **silêncio casando tudo** — nunca dá erro, o
que o torna traiçoeiro.

## Grafana VictoriaLogs: "Nothing to repeat" derruba o painel

**Sintoma:** o Explore quebra com `An unexpected error happened` /
`SyntaxError: Invalid regular expression: /\b(severity_text|count(*)|…)…/:
Nothing to repeat` — em **qualquer** query, não só na atual.
**Causa:** o plugin monta um regex pra destacar nomes de campo nas linhas,
concatenando os campos vistos na sessão. Rodar `| stats count()` **sem alias**
cria a coluna `count(*)` (nome default do count sem alias); o plugin cacheia
esse nome e o injeta no regex — `(` seguido de `*` é regex inválido, e o render
estoura.
**Diagnóstico:** confirmar que não é field armazenado:
`curl .../select/logsql/field_names -d 'query=_time:1h' | jq -r '.values[].value'
| grep -F 'count(*)'` — vazio ⇒ era cache do plugin.
**Fix:** hard-refresh na aba (limpa o cache de campos da sessão) e **sempre
aliasar** agregações: `| stats … count() as n`. Nunca deixar `count()`/`sum()`
sem `as <nome>`.
**Lição:** o bug de fundo é do plugin (não escapa nome de campo antes de montar
`RegExp`, vale issue upstream), mas a causa prática é `count()` sem alias virando
`count(*)` com metachar de regex. Regra operacional: agregação sempre aliasada.

## Lição transversal

`operational`/`VALID`/`selectAllByDefault` não provam target gerado. A prova é o target em
`/api/v1/targets` (`health: up`) e a série no banco — não o status do CR. Query de verdade no
**VMSingle** (8428), não no vmagent (8429, só buffer).
