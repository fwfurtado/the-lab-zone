---
tipo: runbook
componente: backup-dr
tags: [cnpg, barman, velero, rclone, b2, garage, backup, l2-announcement, vmpodscrape, selfheal, cronworkflow]
fases: [9, 10]
relacionado: [runbooks/data-platform, runbooks/network-policies, runbooks/cilium-rede]
---

# Backup e DR: CNPG/Barman, Velero, espelho off-site

Lição transversal da fase (vale relê-la antes de confiar em qualquer dashboard de backup):
**status verde é promessa; a prova é ler o destino.** Apareceu em cada incidente — `bucket info`
(não `ContinuousArchiving`), `arping`/`nc` (não o lease migrar), target em `/api/v1/targets` (não
o CR `operational`), série no banco (não o "0 differences" do check).

## CNPG: backup fantasma desde o dia 1 (quatro camadas)

**Severidade: crítica** — o Postgres (Langfuse/LiteLLM/OpenWebUI/LightRAG) ficou sem backup
nenhum por ~10 dias.
**Sintoma:** `rclone check garage:cnpg-wal` deu "0 differences", mas o bucket estava **vazio**,
enquanto o cluster reportava `ContinuousArchiving: True` e `archived_count` subindo com
`failed_count=0`. WAL "arquivado com sucesso", bucket a zero.
**Causa — quatro camadas empilhadas, cada uma escondia a seguinte:**
1. **Chave de Helm no lugar errado.** `values` tinha o backup sob `cluster.backup.
   barmanObjectStore`; o chart `cloudnative-pg/cluster` espera `backups:` **top-level**. Chave
   inexistente → ignorada em silêncio → `archive_command` virou no-op → exit 0 mentiroso.
2. **Imagem sem barman.** A imagem `...postgresql:18.3-standard-trixie` **não embarca
   `barman-cloud-*`** (extraído pro plugin no CNPG 1.26+; in-tree some no 1.30). `barman-cloud-
   wal-archive: executable file not found`.
3. **Plugin não-descoberto pelo operator.** Migrado pro Barman Cloud Plugin (sidecar), o operator
   (rodando há 9d) não redescobriu o plugin (instalado há 9h): `wal archive plugin is not
   available`.
4. **CNP dropando o sidecar.** Resolvido (3), o barman dava `Connect timeout on garage:3900`. A
   `garage-default-deny-ingress` nunca teve o CNPG na allow-list do `:3900` — o tráfego saía agora
   do sidecar (identidade do pod `cnpg-cluster`) e a CNP o dropava.
**Diagnóstico:** `bucket info` pelo ID físico (não alias); `pg_switch_wal` + bucket seguia 0;
`get cluster -o jsonpath='{.spec.backup}'` vazio (camada 1); `SHOW archive_command` + `ls
/usr/bin/barman*` ausente (camada 2); condition `ContinuousArchiving.message` mudando de "plugin
not available" pra "Connect timeout" (camadas 3→4); Hubble drop no :3900 (camada 4). **Prova final:
** `rclone ls garage:cnpg-wal` listando `base/.../data.tar.gz` + `wals/.../*.gz` (base + cadeia
contígua = PITR real).
**Fix:** Barman Cloud Plugin (manifest do release v0.5.0 commitado); **Cluster vira manifesto cru**
(o chart `cluster` não expressa `.spec.plugins`) com `ObjectStore` CR + `plugins:
[barman-cloud...]` + `ScheduledBackup method: plugin`; 4 envs do Garage no
`instanceSidecarConfiguration.env` (`BARMAN_S3_USE_PATH_STYLE=true`, `AWS_DEFAULT_REGION=garage`,
`AWS_REQUEST_CHECKSUM_CALCULATION=when_required`, `AWS_RESPONSE_CHECKSUM_VALIDATION=when_required`);
restart do operator pra redescobrir o plugin; CNP do Garage com `cnpg.io/cluster: cnpg-cluster` no
`:3900`.
**Lição:**
- **Backup status é promessa, bucket é prova.** `ContinuousArchiving: True` + `failed_count=0`
  conviveram com zero bytes por 10 dias.
- **Chave de Helm inexistente falha em silêncio.** Sempre `helm template | rg` o campo crítico.
- **Imagem `-standard`/`-minimal` do CNPG não tem barman.** Plugin é o caminho.
- **Sidecar herda a identidade do pod, mas a CNP precisa conhecê-la.** Caminho de rede novo = nova
  allow-list, mesmo "sendo o mesmo pod".
- **`instanceSidecarConfiguration` só propaga em rollout do cluster**, e o sidecar é
  `initContainer` nativo — filtrar `.spec.containers` no jsonpath não o acha; usar
  `.spec.initContainers`.

## Gateway some intermitente: nó GPU vira anunciante L2 quebrado

**Severidade: alta** — perda total intermitente de tudo atrás do Gateway.
**Sintoma:** o VIP `10.40.7.10` ficou inacessível, mas `kubectl` respondia normal. `arping
10.40.7.10` → timeout, voltava sozinho às vezes.
**Causa:** a `CiliumL2AnnouncementPolicy` seleciona interfaces por `^ens[0-9]+$`. O `worker-3-gpu`
(hardware diferente) usa **`enp7s0`** — não casa o regex. O Cilium **elegia** o nó GPU como holder
do lease (o `nodeSelector` só excluía control-plane), mas sem interface pra emitir o GARP → VIP
anunciado por ninguém. Intermitente porque só quebrava quando o lease calhava de migrar pro GPU.
**Diagnóstico:** `kubectl` ok + `arping` timeout (falha só no caminho do VIP); `get leases` →
holder `worker-3-gpu`; `delete lease` forçando re-eleição caiu em `worker-1` e o `arping`
respondeu; `ip -br addr` no cilium do GPU → `enp7s0`.
**Fix:** excluir o nó GPU do pool de anúncio (não ampliar o regex — GPU é nó de manutenção
frequente):
```yaml
nodeSelector.matchExpressions:
  - { key: kubernetes.io/hostname, operator: NotIn, values: [worker-3-gpu] }
```
Commit no Git (senão volta no próximo reconcile/failover).
**Validação (failover real):** `cordon worker-1` + `delete lease` → lease no `worker-2`, `arping`
responde, `nc -vz :443` conecta.
**Lição:** lease migrar não prova que o novo holder anuncia (validar `arping`+`nc`). Nó heterogêneo
(`enp` vs `ens`) vira anunciante-fantasma silencioso. Nó de manutenção frequente não deve segurar
VIP crítico.

## `rclone check` "0 differences" enganoso (vazio-vs-vazio)

**Sintoma:** `rclone check garage:cnpg-wal b2:.../cnpg-wal --size-only` → "0 differences" — mas
ambos os lados estavam **vazios** (o cnpg-wal nunca teve dado — ver acima).
**Causa:** `rclone check` compara conjuntos. Vazio vs vazio = 0 diferenças = sucesso sintático, sem
significado de DR.
**Fix:** confirmar contagem não-zero junto com a paridade (`50 matching files, 0 differences`).
**Lição:** "0 differences" só vale com contagem > 0. Vazio-vs-vazio é o falso-verde mais traiçoeiro.

## VMPodScrape `operational` mas sem target (matchExpressions)

**Sintoma:** `velero_backup_failure_total` não existia; o VMPodScrape mostrava `operational`,
selector casava, porta nomeada existia, `selectAllByDefault: true`, RBAC ok — e **zero target** em
`/api/v1/targets`, sem erro.
**Causa:** o VMPodScrape tinha `selector.matchLabels` + `selector.matchExpressions` (um `NotIn`
pra excluir jobs do Kopia). A combinação fazia o operator aceitar o objeto (`operational`) mas
**não gerar o target** — silêncio total.
**Diagnóstico:** `get vmpodscrape -A` (não singular) mostrou `operational`; `diff` contra o
VMPodScrape do `garage` (que funciona) — a única diferença era o `matchExpressions`; após remover +
`rollout restart` do operator, o target apareceu.
**Fix:** VMPodScrape só com `matchLabels`.
**Lição:** objeto `operational` não prova target gerado — a prova é o target `health: up` e a série
no banco. **Diff contra um irmão que funciona** é o atalho mais rápido. Ferramenta engana (`get`
singular com jsonpath errado escondeu o que `get -A` revelou).

## selfHeal do ArgoCD revertendo patches de teste

**Sintoma:** ao corromper o secret B2 / apontar o BSL pra bucket inexistente pra forçar falha, o
backup teimava em sair `Completed`. O patch parecia aplicar mas era revertido em segundos.
**Causa:** `syncPolicy.automated.selfHeal: true` revertia o patch antes do backup executar
(`generation: 1436`); o ESO reforçava no caso do secret.
**Fix:** `argocd app set velero --self-heal=false` durante o teste, aplicar o patch, rodar, religar
`--self-heal=true`.
**Lição:** selfHeal corre mais rápido que a janela de teste — "quebrar de propósito" exige pausar a
reconciliação. (Detalhe: o `VeleroNodeAgentDown` falso-positivo que chegou no Slack durante o debug
já validou a cadeia de alerta ponta a ponta.)

## Backups falhando no ns data (KubeJobFailed) — CNP intra-namespace

**Sintoma:** `KubeJobFailed` em `clickhouse-backup-*` e `qdrant-backup-*`; alguns runs completavam,
outros falhavam (aparência de intermitência).
**Causa:** a default-deny de **ingress** no ns `data` (fase 9) derrubava a conexão `backup-pod →
serviço de dados` DENTRO do próprio namespace.
**Diagnóstico:** `hubble observe --namespace data --verdict DROPPED --follow` mostra
`data/qdrant-backup-...:6333 Policy denied DROPPED (SYN)`. **NÃO** confiar em timeline de Jobs
(Completed vs Failed) — engana; o Hubble flow é o veredito.
**Fix:** allow de ingress intra-namespace pros pods de backup (Qdrant :6333, ClickHouse sidecar
:7171/:9000); limpar os Jobs falhos (`KubeJobFailed` é sticky — só some ao remover o Job).
**Lição:** `KubeJobFailed` fica firing até o Job falho ser removido, mesmo que runs seguintes
passem. Default-deny de ingress derruba conexão pod→pod no mesmo namespace.

## Backups migrados: CronJob → Argo CronWorkflow

- **Qdrant — `containerSet`, não DAG.** O CronJob era `initContainer`(snapshot) +
  `container`(upload) no mesmo pod com `emptyDir`. O equivalente fiel é um `containerSet`: 2
  containers, 1 pod, 1 volume, `dependencies: [snapshot]`. **1 pod = 1 identidade Cilium = 1
  label** — um DAG geraria 2 pods e um round-trip ao bucket `argo-workflows`.
- **ClickHouse — container único** que trigga o sidecar (:7171), com **polling** de
  `/backup/status` (sai com erro se reportar `error`) no lugar do `sleep 30` cego.
- **Identidade estável:** `spec.podMetadata.labels: app.kubernetes.io/name: {qdrant,clickhouse}-
  backup` → as CNPs continuam casando sem alteração.
- **Volume:** o `emptyDir` do containerSet fica em `spec.volumes` do **WorkflowTemplate** e **É
  herdado** pelo `workflowTemplateRef` do CronWorkflow — diferente da verruga do `templateRef` (ver
  `runbooks/argo-workflows/`).
**Lição:** migrar `Job → Workflow` muda identidade (labels), caminho dos logs (`archiveLogs` →
Garage:3900) e modelo de retry. A CNP que valia pro CronJob pode não valer pro Workflow.

## Watchdog + InfoInhibitor chegando ao Slack (plumbing mal roteado)

**Sintoma:** `Watchdog` e `InfoInhibitor` entregues ao Slack, poluindo notificações.
**Causa:** Alertmanager sem `inhibit_rules` nem route pra null receiver. São alertas de **plumbing**
do kube-prometheus (Watchdog = prova de vida; InfoInhibitor = guarda dos `severity=info`), não
incidentes.
**Fix:** sub-route com `alertname =~ "Watchdog|InfoInhibitor"` → receiver `blackhole` (null); +
`inhibit_rules` (warning/critical inibem info do mesmo namespace; InfoInhibitor inibe info do mesmo
namespace). `equal: [namespace]` é crítico.
**Validação:** o dry-run de roteamento é o veredito (`amtool config routes test` retorna
blackhole).
**Lição:** roteamento (null receiver) ≠ inibição. A sub-route esconde do Slack; as `inhibit_rules`
suprimem os `info` reais. Eles continuam `active` no `amtool`/Grafana, mas `Delivered to
...-blackhole` = não chegam no Slack.

## Nota transversal: alertas de saúde do vmagent são reflexos

`TooManyScrapeErrors`/`TooManyLogs` (instance = o próprio vmagent) apontam um **target** falhando,
não problema no vmagent. Achar o target (`curl :8429/targets | rg "down|error="` + logs do vmagent),
NÃO silenciar. Se o operator engasga após muitas mudanças, é transitório — esperar a fila de
reconciliação esvaziar. Resolveram sozinhas ao cessar a causa upstream (etcd downstream; fallout do
VM operator sob carga).

## Lição transversal

**Status verde é promessa; a prova é ler o destino.** Bucket info (não condition), arping/nc (não
lease), target em /targets (não CR operational), série no banco (não "0 diff"). Destino de DR é
sempre B2 (off-site); Garage é tier on-site. selfHeal reverte teste — pausar antes de quebrar de
propósito.
