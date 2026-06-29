---
tipo: runbook
componente: gpu
tags: [dcgm, runtimeclass, daemonset, nvidia, oomkill, distroless, otel-toleration]
fases: [7, 9]
relacionado: [runbooks/talos, runbooks/observability]
---

# GPU: DCGM exporter, RuntimeClass e DaemonSet no nó GPU

Observabilidade da RTX 3090 no `worker-3-gpu`. O taint de GPU é armadilha tanto pro DCGM quanto
pra DaemonSets de telemetria já agendados.

## RuntimeClass `scheduling` não basta para DaemonSet

**Sintoma:** ao subir o DCGM exporter (DaemonSet) só com `runtimeClassName: nvidia`, pods
nascem `Pending`/`Unschedulable` em nós sem GPU.
**Causa:** a injeção de nodeSelector/toleration do bloco `scheduling` da RuntimeClass acontece na
**admissão**. O DaemonSet controller decide os nós lendo o **template** (antes da admissão) →
cria pod em todo nó → os de não-GPU travam.
**Fix:** declarar `nodeSelector` + `toleration` **explícitos** no template do DaemonSet. A
injeção da RuntimeClass por cima é idempotente (mesma chave/valor).
**Lição:** pra DaemonSet, scheduling tem que estar no template — RuntimeClass `scheduling` é
tarde demais pro controller.

## Tag da imagem DCGM: `-distroless`, não `-ubuntu22.04`

**Sintoma:** pull de `...dcgm-exporter:4.5.3-4.8.2-ubuntu22.04` falha (tag inexistente).
**Causa:** as versões 4.x passaram a publicar `-distroless` como padrão; o sufixo `-ubuntu22.04`
foi descontinuado.
**Fix:** usar `4.5.3-4.8.2-distroless`. Verificar com `skopeo list-tags` ou `crane ls`.
**Lição:** distroless não tem shell/curl — probes viram `tcpSocket` e o teste de `/metrics` é
via port-forward, não `exec curl`.

## DCGM exporter em OOMKill com 256Mi

**Sintoma:** o pod entra em OOMKill em loop.
**Causa:** o DCGM roda o `nv-hostengine` **embutido** no container; com `SYS_ADMIN` + métricas
de profiling (`DCGM_FI_PROF_*`) o uso no boot passa dos 256Mi do manifesto oficial.
**Fix:** subir o limit pra `1Gi` (request `256Mi`). Opcional: `counters.csv` curado (sem
`DCGM_FI_PROF_*`) reduz o footprint e tira a dependência do profiling — recomendado em GPU de
consumidor sem MIG.
**Lição:** o `256Mi` do exemplo oficial é otimista pro hostengine embutido + profiling.

## Scrape novo invisível até o vmagent recarregar a config

(Específico do DCGM mas vale pra qualquer scrape novo.) `VMServiceScrape` criado, endpoint vivo,
`selectAllByDefault: true`, sem erro — mas a métrica não aparece e o pool não consta nos
`activeTargets`. Fix: `rollout restart deploy/vmagent-victoria-metrics-vmks`. Ver
`runbooks/observability/` (padrão "operator/vmagent não releu → restart").
> Consumo de GPU por workload: filtrar `exported_namespace`/`exported_pod` (o `honor_labels`
> renomeia as labels do PodMapper; `namespace`/`pod` crus = o próprio exporter).

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

O taint de GPU (`nvidia.com/gpu=present:NoSchedule`) é a raiz de vários incidentes: scheduling
de DaemonSet precisa estar no template (RuntimeClass é tarde), telemetria que já rodava trava
(toleration específica). DCGM precisa de 1Gi e tag distroless. O taint em si vai via
`registerWithTaints` + imperativo — ver `runbooks/talos/`.
