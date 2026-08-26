---
tipo: runbook
componente: gpu
tags: [dcgm, runtimeclass, daemonset, nvidia, oomkill, distroless, otel-toleration]
fases: [7, 9]
relacionado: [runbooks/talos, runbooks/observability]
status: arquivado
---

# GPU: histórico do DCGM exporter, RuntimeClass e DaemonSet

> **Arquivado — não aplicar.** O DCGM exporter foi removido do setup ativo. Não há DaemonSet,
> Service, `VMServiceScrape` ou instrução de instalação DCGM vigente. As seções abaixo registram
> problemas e correções observados quando o exporter existia; não são um procedimento para
> instalá-lo ou reintroduzi-lo.

Observabilidade da RTX 3090 no `worker-3-gpu`: as orientações específicas de DCGM abaixo são
somente contexto histórico. A orientação ainda vigente para o taint é a seção do otel-collector.

## Histórico: RuntimeClass `scheduling` não bastava para DaemonSet

**Situação registrada:** quando o DCGM exporter era um DaemonSet com apenas
`runtimeClassName: nvidia`, pods nasciam `Pending`/`Unschedulable` em nós sem GPU.
**Causa observada:** a injeção de nodeSelector/toleration do bloco `scheduling` da RuntimeClass
acontecia na **admissão**. O DaemonSet controller decidia os nós lendo o **template** (antes da
admissão) e criava pod em todo nó; os de não-GPU travavam.
**Correção histórica:** declarar `nodeSelector` + `toleration` explicitamente no template do
DaemonSet. A injeção da RuntimeClass por cima era idempotente (mesma chave/valor).
**Lição:** para DaemonSets, scheduling tem que estar no template — RuntimeClass `scheduling` é
tarde demais para o controller.

## Histórico: tag da imagem DCGM era `-distroless`, não `-ubuntu22.04`

**Situação registrada:** o pull de `...dcgm-exporter:4.5.3-4.8.2-ubuntu22.04` falhava (tag
inexistente).
**Causa observada:** as versões 4.x passaram a publicar `-distroless` como padrão; o sufixo
`-ubuntu22.04` foi descontinuado.
**Correção histórica:** a imagem usada era `4.5.3-4.8.2-distroless`, verificada com `skopeo
list-tags` ou `crane ls`.
**Lição:** distroless não tinha shell/curl — probes eram `tcpSocket` e o teste de `/metrics` era
via port-forward, não `exec curl`.

## Histórico: DCGM exporter em OOMKill com 256Mi

**Situação registrada:** o pod entrava em OOMKill em loop.
**Causa observada:** o DCGM rodava o `nv-hostengine` **embutido** no container; com
`SYS_ADMIN` + métricas de profiling (`DCGM_FI_PROF_*`) o uso no boot passava dos 256Mi do
manifesto oficial.
**Correção histórica:** o limite foi elevado para `1Gi` (request `256Mi`). Um `counters.csv`
curado (sem `DCGM_FI_PROF_*`) reduzia o footprint e removia a dependência do profiling —
recomendado em GPU de consumidor sem MIG.
**Lição:** o `256Mi` do exemplo oficial era otimista para hostengine embutido + profiling.
Esses valores não são requisitos de nenhum componente ativo.

## Histórico: scrape novo invisível até o vmagent recarregar a config

Este caso era específico do scrape do DCGM e ficou arquivado junto com ele. Um `VMServiceScrape`
era criado, o endpoint estava vivo e `selectAllByDefault: true` não apresentava erro, mas a
métrica não aparecia e o pool não constava nos `activeTargets`. A correção histórica foi
`rollout restart deploy/vmagent-victoria-metrics-vmks`; ver `runbooks/observability/` para o
padrão geral de "operator/vmagent não releu → restart".
> Consumo de GPU por workload: filtrar `exported_namespace`/`exported_pod` (o `honor_labels`
> renomeava as labels do PodMapper; `namespace`/`pod` crus eram o próprio exporter).

## otel-collector DaemonSet travado pelo taint de GPU (MisScheduled + RolloutStuck)

**Sintoma:** `KubeDaemonSetMisScheduled` + `KubeDaemonSetRolloutStuck` no agent do otel.
`DESIRED=2`, mas 3 pods Running.
**Causa:** taint `nvidia.com/gpu=present:NoSchedule` adicionado ao `worker-3-gpu` **depois** do
DaemonSet já ter pod ali. O controller passou a não desejar o nó (3→2), mas o pod pré-taint, sem
toleration, virou órfão misscheduled e travou o rollout. (Timeline: pod do GPU com AGE menor que
os outros marca a data do taint.)
**Fix:** toleration **específica** ao taint conhecido no values do otel:
```yaml
tolerations:
  - { key: nvidia.com/gpu, operator: Equal, value: present, effect: NoSchedule }
```
**Lição:** taint em nó com DaemonSet já agendado não remove o pod existente — gera misscheduled
e trava o rollout. DaemonSet de telemetria é **exceção legítima** ao `NoSchedule` (queremos
observabilidade justo no nó caro/quente). Tolerar **específico**, NÃO `operator: Exists` pelado
(furaria o isolamento de outros nós). Atenção: definir `tolerations` no values **substitui** a
lista default inteira.

## Lição transversal

O taint de GPU (`nvidia.com/gpu=present:NoSchedule`) continua sendo relevante para DaemonSets
de telemetria ativos: toleration específica e scheduling no template. As orientações específicas
de DCGM, inclusive tag, memória e scrape, são somente histórico do componente removido e não
devem ser usadas para instalar nada no cluster atual. O taint em si vai via `registerWithTaints`
+ imperativo — ver `runbooks/talos/`.
