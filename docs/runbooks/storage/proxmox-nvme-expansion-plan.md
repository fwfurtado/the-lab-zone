---
tipo: runbook
componente: storage
tags: [proxmox, nvme, zfs, talos, control-plane, capacity]
---

# Plano de adicao de NVMe no Proxmox

Objetivo: reduzir a contenção de I/O que hoje afeta o control plane do cluster,
criando um pool NVMe dedicado para as VMs mais sensiveis.

## Estado atual

Host: `pve` (`Dell PowerEdge T630`)

### Discos e pools atuais

- `rpool`
  - 2x Kingston SATA 240 GB em mirror
  - uso: boot do Proxmox
- `local-nvme`
  - 2x ADATA LEGEND 900 2 TB em ZFS `stripe`
  - uso: VMs Talos de control plane, discos de boot dos workers e VMs tier-0
- `local-ssd`
  - 1x Crucial MX500 2 TB em `lvmthin`
  - uso: discos auxiliares dos workers, LXC `tailscale`, PVCs locais
- `truenas`
  - 3x HDD 4 TB passthrough para a VM `1104`

### VMs/LXCs relevantes

No `local-nvme`:

- `talos-cp-1` (`100`)
- `talos-cp-2` (`101`)
- `talos-cp-3` (`102`)
- `talos-worker-1` disco de boot (`103`, `virtio0`)
- `talos-worker-2` disco de boot (`104`, `virtio0`)
- `harbor` (`106`)
- `forgejo` (`107`)
- `authentik` (`108`)
- `dns` (`105`)

No `local-ssd`:

- `talos-worker-1` disco auxiliar (`103`, `virtio2`)
- `talos-worker-2` disco auxiliar (`104`, `virtio2`)
- `tailscale` (`1010`)
- boot da VM `truenas` (`1104`)

## Problema que este plano corrige

O incidente observado nao foi falta de CPU nem falta de RAM. A raiz foi:

- control plane e data plane concorrendo no mesmo pool rapido;
- etcd, scheduler e apiserver competindo com VMs e workloads ruidosos;
- `local-nvme` operando sem isolamento por papel;
- `local-nvme` atual em `stripe`, sem redundancia.

Ter 3 control planes ajuda a tolerar melhor a degradacao, mas nao evita a contenção
quando todos dependem do mesmo backend de I/O no mesmo host fisico.

## Decisao de capacidade

Como primeira fase, adicionar **1 NVMe novo** e criar um pool dedicado temporario
para o control plane.

No mes seguinte, adicionar **o 2o NVMe identico** e converter o pool novo para
`mirror`.

## Modelo de compra recomendado

Comprar um par identico de NVMe TLC 2 TB, sem heatsink volumoso, em duas etapas.

Modelos recomendados:

- `Samsung 990 PRO 2TB`
- `WD_BLACK SN850X 2TB`
- `Kingston KC3000 2TB`

Evitar para este papel:

- NVMe QLC
- modelos claramente de entrada
- uso definitivo de SSD DRAM-less para o pool critico

## Fase 1: um NVMe agora

### Objetivo

Separar o control plane do pool `local-nvme` atual, mesmo ainda sem redundancia.

### O que muda

- criar um pool novo ZFS com o NVMe unico
- migrar para esse pool:
  - `talos-cp-1`
  - `talos-cp-2`
  - `talos-cp-3`

### O que nao deve ir nessa fase

Nao colocar ainda nesse pool single-disk:

- workers
- PVCs do cluster
- Harbor
- Forgejo
- cargas volumosas

No maximo, depois da estabilizacao, considerar mover uma VM tier-0 pequena, como
`dns`, se houver motivo operacional claro.

### Beneficio esperado

- queda forte da contenção que afeta etcd/scheduler/apiserver
- menor chance de repetir sintomas como:
  - `Unable to create Service resource`
  - webhooks indisponiveis
  - `Pending` sem evento
  - `etcdserver: leader changed`

### Risco assumido

Durante a Fase 1, o novo pool nao tera redundancia. Se o NVMe unico falhar,
as VMs colocadas nele param.

Por isso, nessa fase, o escopo deve ficar restrito ao control plane.

## Fase 2: segundo NVMe no mes seguinte

### Objetivo

Converter o novo pool dedicado do control plane para `mirror`.

### Resultado esperado

- isolamento de I/O do control plane
- redundancia do pool novo
- desenho estavel para longo prazo

### Depois da Fase 2

Reavaliar se ainda vale comprar 2 SSD SATA adicionais para criar mais folga para
PVCs e VMs nao criticas. Essa segunda compra continua valida, mas deixa de ser
a prioridade numero 1.

## Layout alvo

### Pool NVMe novo

Uso prioritario:

- `talos-cp-1`
- `talos-cp-2`
- `talos-cp-3`

Uso opcional depois do mirror:

- `dns`
- `authentik`
- `forgejo`

### `local-nvme` atual

Permanecem:

- discos de boot dos workers
- discos auxiliares NVMe dos workers
- `harbor`
- VMs nao movidas para o pool critico

### `local-ssd`

Permanecem:

- discos auxiliares SSD dos workers
- PVCs quentes do cluster ja migrados para `openebs-hostpath-ssd`
- `tailscale`
- boot da VM `truenas`

## Ordem de implementacao

1. Comprar 1 NVMe 2 TB
2. Instalar em adaptador PCIe simples, um SSD por placa
3. Criar pool ZFS novo com nome dedicado ao control plane
4. Migrar `talos-cp-1`
5. Validar etcd, scheduler, apiserver e health do cluster
6. Migrar `talos-cp-2`
7. Validar novamente
8. Migrar `talos-cp-3`
9. Observar estabilidade por alguns dias
10. Comprar o 2o NVMe identico
11. Anexar o segundo disco ao pool e converter para `mirror`

## Critério de sucesso

- control plane fora do `local-nvme` compartilhado
- desaparecimento dos sintomas de degradação por contenção
- menor oscilação de scheduler/webhooks/operators sob carga
- pool novo em `mirror` ao final da Fase 2

## Observacoes operacionais

- 1 NVMe novo ajuda a resolver a contenção, mas nao fecha o risco de falha de disco
- o ganho real da Fase 1 e isolamento de I/O, nao alta disponibilidade
- o ganho real da Fase 2 e redundancia
- este plano e mais importante do que aumentar CPU/RAM para o incidente observado
