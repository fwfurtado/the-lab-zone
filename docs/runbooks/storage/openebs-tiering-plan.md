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

## Incidente real de migracao para SSD (2026-07-01)

**Escopo:** migracao online/offline de workloads stateful do tier legado `openebs-hostpath`
(`local-nvme`) para `openebs-hostpath-ssd`, em paralelo a um incidente de control plane.

### O que realmente aconteceu

1. O storage novo (`local-ssd` + `openebs-hostpath-ssd`) foi criado corretamente.
2. As migracoes de PVC reduziram pressao no `local-nvme`, mas durante a janela houve
   oscilacao do control plane (`etcdserver: leader changed`, scheduler/operator perdendo lease).
3. O caso mais sensivel foi o `data/cnpg-cluster`:
   - PVC antigo foi copiado para um PVC temporario de seguranca (`cnpg-cluster-migration`);
   - o restore do CNPG no PVC novo chegou a travar varias vezes por sintomas **secundarios**
     do control plane: Kyverno webhook indisponivel, `barman-cloud` flapping, pod do recovery
     preso em `Pending` sem evento;
   - depois que o restore completou, o `cnpg-operator` ainda falhou na extracao de status por
     mismatch de certificado entre `cnpg-cluster-server` e `cnpg-cluster-ca`;
   - a correcao foi rotacionar `cnpg-cluster-server` e `cnpg-cluster-replication`, validar o
     par com `openssl verify`, e so entao retomar a reconciliacao.

### Sinais que distinguiram problema de storage vs problema de control plane

**Parecia storage/localpv:**
- pods de recovery e do banco presos em `Pending`;
- PVC novo em `initializing` por varios loops;
- apps do Argo em `Unknown`/`Processing`.

**Era control plane/operator em cascata:**
- `kube-scheduler` em `CrashLoopBackOff`/perda de lease;
- pod `Pending` sem `FailedScheduling`;
- `cnpg-webhook-service` sem endpoint pronto;
- `cnpg-operator` perdendo lease e falhando em plugin/webhook;
- `kubectl` intermitente com `etcdserver: leader changed` e `request timed out`.

### Mitigacao que funcionou

- manter sempre um PVC temporario/copia offline antes da troca definitiva de `storageClass`;
- para restore CNPG:
  - usar backup valido confirmado (`backupId`);
  - pausar autosync do app durante o DR;
  - recriar job/pod de recovery quando o scheduler destravava;
  - usar bind explicito do pod ao node quando o scheduler ficou preso sem evento;
  - rotacionar os certs do CNPG se o operator reportar
    `tls: failed to verify certificate` ao ler `/pg/status`.
- para o cluster em geral:
  - so considerar a migracao encerrada quando Argo voltar a `Synced/Healthy`,
    `cnpg-operator`/webhook estiverem `Running`, e o workload responder funcionalmente.

### Licoes especificas

- trocar `storageClass` nao migra dado; copia offline ou backup/restore continua obrigatorio;
- numa migracao stateful, `Pending` sem evento quase sempre e scheduler/control plane, nao PVC;
- para CNPG, o estado funcional do banco (`pg_is_in_recovery() = false`, service `rw`
  apontando pro pod) vale mais do que o `status.phase` durante a oscilacao do operator;
- mismatch de cert do CNPG pode aparecer **depois** do restore e mascarar um cluster ja
  funcional;
- separar os stores ruidosos do `local-nvme` continua correto; o que prolongou o incidente
  foi a instabilidade do control plane, nao o tiering em si.
