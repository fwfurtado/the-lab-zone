---
tipo: runbook
componente: storage
tags: [openebs, localpv, proxmox, talos, migration]
---

# OpenEBS tiering plan: local-nvme + local-ssd

Objetivo: separar o tier de dados persistentes dos workers do pool `local-nvme`
que hoje tambem sustenta os discos das VMs do control plane.

## Layout alvo

- `local-nvme`
  - discos de boot das VMs Talos
  - control plane
  - tier legado `openebs-hostpath` em `/var/mnt/pv-data`
- `local-ssd`
  - segundo disco dos workers (`virtio2`)
  - novo tier `openebs-hostpath-ssd` em `/var/mnt/pv-data-ssd`

## Implementacao no repo

- Terraform dos workers com segundo disco opcional `pv_ssd_disk_size`
  em `local-ssd`
- Talos com segundo `UserVolumeConfig`:
  - `pv-data` -> `/var/mnt/pv-data` (legado NVMe)
  - `pv-data-ssd` -> `/var/mnt/pv-data-ssd`
- Nova `StorageClass`:
  - `openebs-hostpath-ssd`

## Selectors dos discos

Nos workers atuais, os discos foram confirmados via `talosctl get disks`:

- tier legado NVMe: `/dev/vdb`
- tier SSD novo: `/dev/vdc`

Os `UserVolumeConfig` usam `disk.transport == "virtio"` combinado com `disk.dev_path`
para evitar depender apenas de tamanho.

## Regra operacional

Trocar `storageClassName` **nao migra dados**. Qualquer workload stateful precisa
de uma migracao explicita (backup/restore, snapshot/restore ou copia offline de PVC).

## Alocacao recomendada por tier

### Deve migrar para `openebs-hostpath-ssd`

- `data/cnpg-cluster`
- `data/clickhouse`
- `data/qdrant`
- `data/memgraph`
- `data/garage`
- `data/valkey`
- `observability/vmsingle-victoria-metrics-vmks`
- `observability/victoria-logs-vls-server`

### Pode migrar depois para `openebs-hostpath-ssd`

- `observability/grafana`
- `ai/open-webui`
- `ai/lightrag-data`

### Deve permanecer fora desse tier

- `ai/ollama-models`
- `ai/next-edit-models`

Esses dois devem continuar node-local no worker GPU.

## Ordem de migracao sugerida

1. `observability/victoria-logs-vls-server`
2. `observability/vmsingle-victoria-metrics-vmks`
3. `data/valkey`
4. `data/cnpg-cluster`
5. `data/qdrant`
6. `data/memgraph`
7. `data/clickhouse`
8. `data/garage`
9. `observability/grafana`
10. `ai/open-webui`
11. `ai/lightrag-data`

## Critério de sucesso

- `openebs-hostpath-ssd` criada e nao-default
- `pv-data-ssd` montado nos workers
- workloads mais ruidosos fora do `local-nvme`
- menos oscillacao de etcd/apiserver sob carga de apps
