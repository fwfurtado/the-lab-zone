---
tipo: runbook
componente: storage
tags: [openebs, localpv, hostpath, mayastor, logging, terraform, podsecurity]
fases: [4]
relacionado: [decisions/0009-storage-localpv-hostpath]
---

# OpenEBS LocalPV hostpath: logging vestigial e chaves do chart

## Stack de logging do Mayastor (loki + alloy + minio) provisionada sem o engine

**Sintoma:** após o sync, o namespace `openebs` ganhou pods de **MinIO, Alloy e Loki**, mesmo
com o engine Mayastor desligado.
**Causa:** esse trio é o stack de logging do subchart do Mayastor (Loki guarda, Alloy coleta,
MinIO é o storage do Loki). No umbrella 4.5.0 os flags `loki:` e `alloy:` são **chaves
top-level** com `enabled: true` próprio, **não atrelados** a `engines.replicated.mayastor.
enabled`. Desligar o engine mata o data plane do Mayastor (io-engine, etcd), mas não cascateia
pros subcharts de logging.
**Diagnóstico:** ler os defaults do chart 4.5.0 confirma que `loki`/`alloy` estão top-level, e
que `mayastor.loki`/`mayastor.alloy` já vêm `false` (são os do subchart, diferentes). O MinIO
não é chave de topo — é storage interno do Loki, cai junto ao desligar o Loki.
**Fix:** `loki.enabled: false` + `alloy.enabled: false` no values. Com `prune: true`, o ArgoCD
remove os recursos sozinho.

## Chaves vestigiais do localpv-provisioner

**Sintoma:** `localpv-provisioner.openebsNDM.enabled` e `deviceClass.enabled` no values não
surtiam efeito.
**Causa:** o `localpv-provisioner` v4 **removeu o device mode e o NDM**; essas chaves não
existem mais e o Helm as ignora (no-op).
**Fix:** removidas. Sobra só `hostpathClass.enabled: false` (desliga a StorageClass default do
chart, já que usamos a nossa, gerenciada por nós com `BasePath` determinístico).

## (Verificação, não falha) Plano do Terraform podia recriar a VM

**Sintoma potencial:** anexar disco poderia disparar `-/+ replace` e destruir o nó Talos.
**Diagnóstico:** o `tf-plan` mostrou `0 to destroy` / `2 to change` (update in-place) — disco
anexado a quente (virtio hot-plug), sem reboot dos workers.
**Nota:** sempre conferir o plano antes do apply; nesse ponto ainda não há dado no disco de PV,
então mesmo um recreate seria recuperável.

## node-exporter / helper pods exigem PodSecurity privileged

O namespace `openebs` precisa de `pod-security.kubernetes.io/enforce: privileged` (helper pods
do provisioner montam hostPath e rodam privilegiados), via `namespace.yaml` com `sync-wave:
"-1"`. Mesma classe da isenção do node-exporter (`runbooks/observability/`) e do DCGM
(`runbooks/gpu/`).

## Lição transversal

Desligar um engine de chart umbrella não desliga subcharts de logging/observabilidade
top-level — conferir os defaults do chart e desligar explícito. StorageClass gerenciada por
nós (não pelo chart) dá controle determinístico do `BasePath` apontando pro user volume Talos.
