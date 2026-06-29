---
tipo: runbook
componente: network-policies
tags: [ciliumnetworkpolicy, default-deny, audit-mode, fromendpoints, fromentities, hubble, cross-namespace, archivelogs]
fases: [9]
relacionado: [runbooks/cilium-rede, runbooks/argo-workflows, runbooks/backup-dr]
---

# Cilium Network Policies: default-deny ingress

Default-deny **ingress** em `data` e `ai`, app por app, via Policy Audit Mode. O ritual padrão
está no fim. Fronteira GitOps: `manifests/` = enforçado; `pending/` = baseline em audit, aplicada
à mão, fora do GitOps; promoção = `git mv pending/ → manifests/`.

## `ingress: []` é INVÁLIDO no CRD

**Sintoma:** CNP aplicada mas `VALID: False`; nenhum efeito.
**Causa:** lista de ingress vazia (`[]`) viola o validador (`rule must have at least one of
Ingress, IngressDeny, Egress, EgressDeny`).
**Fix:** default-deny ingress puro = **`ingress: - {}`** (uma regra presente porém vazia = nenhuma
origem permitida = nega tudo, e passa na validação).
**Lição:** `ingress: []` ≠ `ingress: - {}`. O `[]` é inválido; o `- {}` é o default-deny. E `- {}`
**não** é allow-all (allow-all seria `fromEntities: [all]`).

## `enableDefaultDeny` sozinho não enforça

**Causa:** setar só `enableDefaultDeny.ingress: true` sem nenhuma stanza de regra não ativa o
default-deny (cilium #35558).
**Lição:** precisa da seção `ingress` com regra (`- {}`); o campo sozinho é insuficiente.

## CNP `VALID: False` silenciosa → audit sem efeito

**Sintoma:** audit mode `Enabled`, mas `hubble observe` vazio com tráfego fluindo.
**Causa:** a CNP estava `VALID: False` → não aplicada a endpoint nenhum → endpoint com
`policy-enabled: none` → audit sem efeito (não há policy pra auditar).
**Diagnóstico:** `cilium-dbg endpoint get <id>` mostra `policy-enabled: none` em vez de `ingress`.
**Lição:** depois de aplicar uma CNP, **sempre** conferir `VALID: True` **e** o `policy-enabled`
do endpoint antes de confiar que o audit observa.

## Audit vem `Disabled` por padrão → bloqueio real

**Sintoma:** apps `Policy denied DROPPED` na 5432 ao aplicar a baseline do Postgres.
**Causa:** `PolicyAuditMode` vem `Disabled`; aplicar a default-deny sem ligar o audit **antes** =
enforcement imediato.
**Fix:** deletar a CNP pra destravar; reaplicar **só após** `audit ... Enabled` confirmado em
**todos** os pods do alvo.
**Lição:** ordem obrigatória: ligar audit → confirmar Enabled → aplicar baseline. Nunca aplicar
default-deny sem o audit ativo.

## `PolicyAuditMode` é imperativo e não persiste

**Causa:** não é campo de recurso K8s — é opção de runtime do endpoint (`cilium-dbg endpoint
config`, ID efêmero). Não declarável em GitOps; reseta em restart do agent/pod.
**Fix:** encapsular o ritual no `mod.just` (`audit Enabled/Disabled`).
**Lição:** o audit é andaime de transição, não estado desejado — fica fora do Git. Janela curta
por app (restart re-tranca se a CNP já existe).

## Pool de conexão persistente esconde os SYN

**Sintoma:** cliente claramente usando o serviço, mas nenhum verdict de policy.
**Causa:** o policy-verdict é avaliado na **abertura** (SYN). Pools persistentes reusam conexões
abertas antes da policy → sem SYN novo.
**Fix:** `kubectl rollout restart` no **cliente** (não no destino) pra forçar reabertura.
**Lição:** "sem verdict" ≠ "sem tráfego". E o buffer do Hubble gira rápido — usar `--follow`
durante o restart, não `--last` depois.

## Labels que fogem do padrão `app.kubernetes.io/name`

- **CNPG:** `cnpg.io/cluster: <nome>`; não filtrar por `instanceRole` (cobre primário+réplicas,
  sobrevive a failover).
- **ClickHouse (Altinity):** `clickhouse.altinity.com/chi: <chi>`.
**Lição:** confirmar sempre com `kubectl get pod --show-labels` antes do `endpointSelector`.

## Argo Workflows — pods sem label estável

**Sintoma:** o ELT aparecia no AUDIT com pods cujo único label útil
(`workflows.argoproj.io/workflow`) muda a cada run.
**Fix:** `spec.podMetadata.labels` fixo no **WorkflowTemplate** (propaga a todos os pods,
inclusive os de `templateRef`).
**Lição:** policy que mira workload efêmero (job/workflow) exige um label estável **adicionado** ao
template.

## Cross-namespace exige o label de namespace no `fromEndpoints`

**Causa:** sem `io.kubernetes.pod.namespace: <ns>`, o `matchLabels` casa só dentro do namespace da
própria CNP.
**Fix:** todo `fromEndpoints` cross-namespace leva `io.kubernetes.pod.namespace` junto do label do
app.
**Lição:** allow entre namespaces sem o label de namespace simplesmente não casa.

## Origem `ingress` (Gateway/Envoy) usa `fromEntities`, não `fromEndpoints`

**Sintoma:** app exposto via Gateway com source identity `reserved:ingress`.
**Causa:** o último hop é o Envoy do Cilium Gateway, identidade reservada — não um pod.
**Fix:** `fromEntities: [ingress]` (+ `health`/`host` se aparecerem probes do kubelet no AUDIT).
**Lição:** identidades reservadas (`ingress`, `host`, `health`, `world`, `remote-node`) →
`fromEntities`. Errar a regra do app exposto **derruba a própria UI** — validar abrindo a URL.

## Fluxos esporádicos só aparecem quando rodam

**Sintoma:** o ELT (CronWorkflow) só apareceu no AUDIT quando o schedule disparou.
**Fix:** cobrir um **ciclo completo**; disparar manualmente o que for raro (ELT, backup) antes de
promover. Deixar `--verdict DROPPED` rodando após enforçar como rede de segurança.
**Lição:** o maior risco do default-deny é o fluxo que você não viu.

## Operator CNPG não precisou da 5432 (decisão conservadora)

O `cloudnative-pg` gerencia o cluster via instance manager (8000); restart re-sincronizou sem
dropar na 5432. **Decisão:** mesmo assim liberar 5432 + 8000 pro operator (conservador) — custo
~zero, cobre operações raras (failover, scale-up, restore).
**Lição:** pra banco, a precaução numa regra barata vale mais que o minimalismo.

## `archiveLogs` do Argo cria dependência de rede invisível → Garage:3900

**Sintoma:** após migrar backups pro Argo, surgiram fluxos pra `garage:3900` que não existiam no
desenho: `clickhouse-backup`, `analytics-etl` (ns data) e — ao abrir um run na UI —
`argo-workflows-server`.
**Causa:** `artifact-repositories` tem `archiveLogs: true`, com **dois lados** não escritos no
manifesto: (1) **escrita** — o sidecar `wait` de todo pod de Workflow arquiva logs no Garage:3900
ao concluir; (2) **leitura** — o `argo-workflows-server` lê de volta pra servir os logs na UI.
**Fix:** liberar a 3900 pra todos os clientes do artifact repo — produtores (ns data:
`qdrant-backup`, `clickhouse-backup`, `analytics-etl`) e leitor (ns argo-workflows:
`argo-workflows-server`).
**Diagnóstico:** validar exercitando um run E **abrindo a UI dele** (senão o fluxo do server não
aparece): `hubble observe --to-label app.kubernetes.io/name=garage --port 3900 --follow`.
**Lição:** `archiveLogs` é dependência de rede **transversal**, não do app. O mapa de "quem fala
com o artifact repo" é: todo pod de workflow (escrita) + o server (leitura) + (se ligar
`artifactGC`) os pods de GC (delete).

# Parte 3 — Observabilidade de drops (alerta → Slack)

Cadeia: `hubble_drop_total` → VMRule `CiliumPolicyDrop` → vmalert → vmalertmanager → Slack.

## Hubble não exporta métricas Prometheus

**Sintoma:** `hubble_drop_total` não existe no VM.
**Causa:** o bloco `hubble` tinha só `relay` e `ui`, **sem `metrics`**. Observar (UI/CLI) e
exportar (metrics) são coisas separadas.
**Fix:** `hubble.metrics.enabled` com `drop:labelsContext=source_namespace,destination_namespace,
traffic_direction`, `flow`, `tcp`, `dns` + `enableOpenMetrics: true`.
**Lição:** `drop` não vem por padrão; `labelsContext` é o que dá origem/destino. Evitar
`source_ip`/`destination_ip` (cardinalidade).

## A 9965 pareceu servir gRPC em vez de flow metrics

**Causa:** o curl foi no IP do **nó** (a 9965 tem `hostPort`), e pegou outro listener.
**Fix:** testar de dentro via port-forward no **service** (`svc/hubble-metrics 9965:9965`) →
`grep -E "^hubble_(drop|flow)"`. O log do agent (`Starting Hubble metrics server`) é a fonte da
verdade de onde o server subiu.

## VMServiceScrape cross-namespace não vira target

**Causa:** o `namespaceSelector` do VMServiceScrape no VM operator é inconsistente — casa services
do **próprio** namespace do scrape.
**Fix:** mover o VMServiceScrape pra `kube-system` (mesmo ns do service), `selector k8s-app=hubble`,
port `hubble-metrics` (nome). **E reiniciar o operator.**
**Lição:** VMServiceScrape junto do service que ele scrapeia.

## VMRule não materializada / scrape não vira config → RESTART operator (3x)

`VMRule`/`VMServiceScrape`/config do alertmanager criados, válidos, `selectAllByDefault: true`, mas
não aparecem. Causa: reconciliação travada do operator. **Aconteceu 3x nesta fase.** Fix: `rollout
restart` do operator (ver `runbooks/observability/`).

## Alerta não fira no teste por burst vs `for:`

**Causa:** o `for: 2m` exige `rate(...[5m])` positivo por 2min contínuos; burst pontual some antes.
**Fix:** drop **sustentado** > 2min (`while true; do curl -m 2 -s http://<ip>:8123; sleep 3; done`).
**Lição:** drop por policy é **timeout** no curl (sem RST/refused), não erro de conexão.

## `useManagedConfig: false` mantém o blackhole e ignora VMAlertmanagerConfigs

**Sintoma:** alerta fira, mas não vai pro Slack; o config do alertmanager segue
`route.receiver: blackhole`, mesmo com `selectAllByDefault`/`disableNamespaceMatcher` e o config
`Synced`.
**Causa:** o chart vmks tem `config` default (blackhole). Com `useManagedConfig: false` (default),
o chart materializa esse config num Secret e seta `configSecret` no VMAlertmanager. **Enquanto
`configSecret` está setado, o operator IGNORA todos os VMAlertmanagerConfigs.**
**Fix:** `alertmanager.useManagedConfig: true` — o chart deixa de setar `configSecret`; o operator
combina os VMAlertmanagerConfigs. Confirmar `configSecret` vazio.
**Lição:** remover `alertmanager.config` não desliga o config default; `useManagedConfig: true` é
o que libera os VMAlertmanagerConfigs.

## Secret `-config` defasado após trocar `useManagedConfig`

A fonte da verdade do alertmanager é o config no **pod** (`/etc/alertmanager/config_out/*.yaml`),
não o secret `-config` (que pode defasar). A prova definitiva é o comportamento: alerta no Slack >
leitura de um secret possivelmente obsoleto.

## VMAlertmanagerConfig — snake_case no route + namespace matcher

- **snake_case:** `repeat_interval`, `group_wait`, `group_interval`, `group_by` (não camelCase).
  Conferir com `kubectl explain vmalertmanagerconfig.spec.route --recursive`.
- **namespace matcher forçado:** alertas precisam de label `namespace=<ns-do-config>`; o
  `CiliumPolicyDrop` tem `destination_namespace`, não casaria. Fix: `disableNamespaceMatcher: true`
  no VMAlertmanager.

## Integração Grafana (ver alertas/regras)

Três peças via values: Alertmanager datasource (`type: alertmanager`, url do vmalertmanager:9093);
`vmalert.proxyURL` no `vmsingle.spec.extraArgs`; `jsonData.manageAlerts: true` no datasource VM.
"Ver regras" (proxyURL + manageAlerts) e "ver firing" (Alertmanager datasource) são telas
diferentes.

## Ritual padrão por app (referência rápida)

```
1. label real + nº de pods:  kubectl -n <ns> get pod -l <selector> --show-labels
2. LIGA audit ANTES (vem Disabled!) + confirma Enabled em TODOS os pods
3. aplica baseline (pending/, à mão); confere VALID:True e policy-enabled:ingress no endpoint
4. observa (força reconexão dos clientes p/ os SYN): hubble observe -t policy-verdict --follow
5. cada AUDIT vira allow (fromEndpoints+toPorts; fromEntities p/ ingress/host/health);
   refina até zerar AUDIT, cobrindo 1 ciclo completo (inclui crons/backups)
6. PROMOVE: git mv pending/ → manifests/; audit Disabled (vira enforcement)
7. rede de segurança: hubble observe --verdict DROPPED --follow
```

## Lição transversal

Default-deny de ingress derruba conexão pod→pod **dentro do mesmo namespace**. A ordem é sagrada:
audit ON → confirmar → baseline. `VALID:True` + `policy-enabled:ingress` antes de confiar no
audit. Hubble flow é a fonte da verdade (não timeline de Jobs). O operator VM não materializa →
restart (3x). `archiveLogs` e pools persistentes criam fluxos invisíveis — exercitar ciclo
completo.
