---
tipo: runbook
componente: data-platform
tags: [spark, garage, victoriametrics, talos, proxmox, major-page-faults, node-affinity, vmrule]
fases: [5, 6, 8]
relacionado: [runbooks/data-platform/garage-clickhouse-cnpg-stores.md, runbooks/observability/alertas-operacionais.md, runbooks/talos/control-plane-etcd-gpu-taints.md]
---

# Incidente 2026-07-20 — Spark, Garage e VictoriaMetrics sem headroom

## Sintomas

Alertas recebidos:

```text
TooHighMemoryUsage namespace=observability
It is more than 80% of memory used by "vmsingle-victoria-metrics-vmks"("10.245.3.247:8428")
```

```text
NodeMemoryMajorPagesFaults namespace=observability
Memory major pages are occurring at very high rate at 10.40.6.22:9100,
500 major page faults per second for the last 15 minutes, is currently at 510.00.
```

Impacto observado:

- `vmsingle` ficou próximo do limite de memória de `2Gi`.
- `worker-2` gerou picos de major page faults acima de `500/s`.
- Não houve OOM/restart do `vmsingle` durante o incidente.
- O alerta de node usava `namespace=observability` porque o target era o `node-exporter`; isso não significa que o culpado estava nesse namespace.

## Linha do tempo resumida

- `vmsingle` estava em `worker-1`, IP do pod `10.245.3.247`.
- `NodeMemoryMajorPagesFaults` foi em `worker-2`, target `10.40.6.22:9100`.
- Janelas de `pgmajfault > 500/s` no `worker-2`:

```text
2026-07-20 01:19 → 01:23 -03   ~4m
2026-07-20 02:19 → 04:23 -03   ~124m
2026-07-20 08:10 → 08:54 -03   ~44m
```

- `worker-4-compute` foi criado depois do diagnóstico para isolar compute:

```text
hostname: worker-4-compute
IP: 10.40.6.24
label: node-role.lab/compute=true
taint: workload.lab/compute=true:NoSchedule
capacity: 16 CPU / ~64GiB RAM / ~200GiB ephemeral
```

## Diagnóstico — VictoriaMetrics

Regra do alerta:

```promql
(min_over_time(process_resident_memory_anon_bytes[10m]) / vm_available_memory_bytes) > 0.8
```

Config antiga do `vmsingle`:

```yaml
requests:
  cpu: 200m
  memory: 512Mi
limits:
  memory: 2Gi
```

Dados coletados no dia:

```text
process_resident_memory_anon_bytes / vm_available_memory_bytes
min: 73.89% às 07:55
max: 87.71% às 04:35
avg: 82.13%

rss / vm_available_memory_bytes
max: 93.72%
avg: 88.24%
```

Composição da memória do `vmsingle`:

```text
cache total: 821Mi → 953Mi
Go heap in-use: 635Mi → 924Mi
storage/tsid cache: ~480Mi
indexdb/dataBlocks: ~168Mi → 213Mi
storage/indexBlocks: ~57Mi → 111Mi
```

Ingestão subiu:

```text
2026-07-18: ~16.75k rows/s
2026-07-19: ~17.37k rows/s
2026-07-20: ~20.43k rows/s
```

Principais aumentos de amostras por scrape:

```text
apiserver:       +19,503 samples/scrape
policy-reporter:  +2,941 samples/scrape
kubelet:            +664 samples/scrape
kube-state-metrics: +597 samples/scrape
hubble-metrics:     +535 samples/scrape
```

Conclusão: o `vmsingle` tinha pouco headroom para o volume atual. O alerta refletiu caches/heap normais do VictoriaMetrics operando perto demais de `2Gi`, não um OOM nem leak confirmado.

## Diagnóstico — major page faults no worker-2

O alerta foi no node:

```text
worker-2 / 10.40.6.22:9100
```

Memória do node durante a janela:

```text
MemAvailable min: 13.47GiB
MemAvailable max: 17.89GiB
MemoryPressure: False
SwapTotal: 0
memory PSI stalled/waiting: 0
```

Logo, não era falta global de RAM do node.

O contador de major faults acompanhava reads pequenos do disco:

```text
rate(node_vmstat_pgmajfault[5m]) ~= rate(node_disk_reads_completed_total[5m])
```

Isso apontou para leituras frias/page cache churn.

### Processo responsável

Foram coletados `/proc/<pid>/stat` no `worker-2`.

Spark executors:

```text
generator-accounts executor PID 215690:
  minflt=974016
  majflt=0

cdf-to-kafka executor PID 115313:
  minflt=394909
  majflt=3
```

Eles não eram a fonte direta dos major faults.

Garage:

```text
/garage server PID 11715:
  minflt=153,265,663
  majflt=15,360,696
```

Amostra de 15s:

```text
majflt 15,362,275 → 15,362,812
delta 537 / 15s = ~35.8 major faults/s
```

Conclusão: o processo direto gerando major faults era o Garage. Os jobs Spark provavelmente induziam I/O S3/Delta; o Garage, co-localizado no mesmo node, fazia leituras frias e faultava páginas do disco.

## Causa raiz

Duas causas independentes, mas reveladas pelo mesmo aumento de carga:

1. `vmsingle` subdimensionado para o volume/cardinalidade atual.
2. Garage e Spark/data jobs co-localizados no `worker-2`, competindo por page cache e disco local da mesma VM/cgroup.

A VM nova no mesmo Proxmox/NVMe não aumenta I/O físico, mas isola:

- page cache por VM;
- cgroups;
- kubelet eviction;
- scheduling;
- blast radius de jobs compute.

## Correções aplicadas em Git

### `vmsingle` com mais headroom

Arquivo:

```text
apps/observability/victoria-metrics/values.yaml
```

Novo sizing:

```yaml
requests:
  cpu: 200m
  memory: 2Gi
limits:
  memory: 4Gi
```

### Garage com mais espaço de cache no cgroup

Arquivo:

```text
apps/data/garage/values.yaml
```

Novo sizing:

```yaml
resources:
  requests:
    cpu: 100m
    memory: 1Gi
  limits:
    memory: 2Gi
```

Observação: o StatefulSet do Garage usa `updateStrategy: OnDelete`; o pod `garage-0` só pega o novo recurso quando recriado.

### Worker compute dedicado

Arquivos:

```text
infra/prod/talos/variables.tf
infra/prod/talos/talconfig.yaml
infra/prod/talos/clusterconfig/lab-zone-worker-4-compute.yaml
```

VM criada:

```text
worker-4-compute
10.40.6.24
16 vCPU
64GiB RAM
200GiB boot/ephemeral
120GiB /dev/vdb para UserVolumeConfig pv-data
```

Labels/taints:

```yaml
node-role.lab/compute: "true"
workload.lab/compute=true:NoSchedule
```

### SparkApplications movidas para compute

Arquivos:

```text
apps/data/lakehouse/manifests/generator/generator-accounts.yaml
apps/data/lakehouse/manifests/streaming/streaming-cdf.yaml
apps/data/lakehouse/manifests/migrations/migrate.yaml
```

Driver e executor receberam:

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: node-role.lab/compute
              operator: In
              values:
                - "true"
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/name: garage
            app.kubernetes.io/instance: garage
        topologyKey: kubernetes.io/hostname
tolerations:
  - key: workload.lab/compute
    operator: Equal
    value: "true"
    effect: NoSchedule
```

Semântica importante:

- `requiredDuringSchedulingIgnoredDuringExecution` só vale no próximo scheduling.
- Pods já rodando não são movidos automaticamente.
- Para mover agora, recriar driver/executor.
- Se `worker-4-compute` ficar indisponível, os Spark pods ficam `Pending`; isso é intencional para preservar isolamento.

### Alertas para SparkApplications

Arquivo:

```text
apps/data/lakehouse/manifests/vmrule.yaml
```

Regras:

```text
SparkGeneratorAccountsNotRunning
SparkStreamingCdfNotRunning
SparkLakehouseMigrateBlocked
```

`lakehouse-migrate` é one-shot: ausência/Succeeded é normal. O alerta dele só dispara se o driver existir e ficar `Pending|Unknown|Failed` por 10m.

## Diagnóstico rápido se voltar

### `TooHighMemoryUsage` no vmsingle

```bash
kubectl -n observability top pod vmsingle-victoria-metrics-vmks-798674685d-h5hvq --containers
kubectl -n observability get vmsingle victoria-metrics-vmks -o yaml
```

PromQL útil:

```promql
100 * process_resident_memory_anon_bytes{service="vmsingle-victoria-metrics-vmks"}
  / vm_available_memory_bytes{service="vmsingle-victoria-metrics-vmks"}

sum(vm_cache_size_bytes{service="vmsingle-victoria-metrics-vmks"}) by (type)

sum(rate(vm_rows_inserted_total{service="vmsingle-victoria-metrics-vmks"}[5m]))
```

### `NodeMemoryMajorPagesFaults`

1. Confirmar o node:

```promql
rate(node_vmstat_pgmajfault[5m])
```

2. Ver se é falta real de RAM:

```promql
node_memory_MemAvailable_bytes
rate(node_pressure_memory_stalled_seconds_total[5m])
rate(node_pressure_memory_waiting_seconds_total[5m])
node_memory_SwapTotal_bytes
```

3. Comparar com reads de disco:

```promql
sum(rate(node_disk_reads_completed_total[5m])) by (instance)
```

4. Se for `worker-2`, medir Garage:

```bash
talosctl --talosconfig=infra/prod/talos/clusterconfig/talosconfig \
  --nodes=10.40.6.22 read /proc/11715/stat
```

Campos em `/proc/<pid>/stat`:

```text
field 10 = minflt
field 12 = majflt
```

Coletar dois snapshots com 15–60s de intervalo e calcular delta de `majflt`.

### Spark preso no compute node

```bash
kubectl -n data get sparkapplications -o wide
kubectl -n data get pods -o wide -l spark-role=driver
kubectl describe node worker-4-compute
```

Conferir:

```text
node Ready
label node-role.lab/compute=true
taint workload.lab/compute=true:NoSchedule
Spark pod com toleration correspondente
```

## Critérios de resolução

- `vmsingle` abaixo de 80% sustentado ou com headroom suficiente após resize.
- `rate(node_vmstat_pgmajfault{instance="10.40.6.22:9100"}[5m])` sem janelas sustentadas acima de `500/s`.
- Spark driver/executor em `worker-4-compute`.
- Garage não co-localizado com Spark driver/executor.
- VMRule `lakehouse-spark` carregada pelo VMAlert.

## Lição

Não misturar storage stateful e compute ruidoso no mesmo node quando o storage depende de page cache. Em Proxmox com o mesmo NVMe, node novo não cria I/O físico novo, mas cria isolamento operacional suficiente para reduzir churn de cache, eviction e blast radius.
