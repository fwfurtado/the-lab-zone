---
tipo: setup
fase: 4
titulo: Fundação de storage — LocalPV hostpath
relacionado: [decisions/0007-storage-localpv-hostpath-anti-fake-ha]
---

# Setup Fase 4 — Storage LocalPV hostpath

Entrega o tier quente RWO: StorageClass `openebs-hostpath` num disco dedicado por worker
(`/dev/vdb` → `/var/mnt/pv-data`). Ordem que não inverte: **disco → user volume → app de
storage**.

## 4.1 Proxmox: disco de PV dedicado nos workers
Segundo disco (`virtio1`) condicional só pros nós com `pv_disk_size` (workers), `backup = false`.
Exit: `tf-plan` mostra `0 to add, 2 to change, 0 to destroy` (in-place, CPs intocados).

## 4.2 Talos: user volume (formata + monta)
`UserVolumeConfig` `pv-data` (`diskSelector match: '!system_disk'`, xfs) via overlay `worker:` do
talhelper. `talhelper genconfig` + `talosctl apply-config` nos workers (runtime, sem reboot).
Exit: `u-pv-data` em PHASE=ready e `/var/mnt/pv-data` montado (~200G) nos dois workers.

## 4.3 ArgoCD: whitelist do repo OpenEBS
Adicionar `https://openebs.github.io/openebs` aos `sourceRepos` do `projects/core.yaml`.

## 4.4 OpenEBS LocalPV hostpath
App multi-source, chart `openebs` 4.5.0, **só** o engine hostpath ligado, logging do Mayastor
(loki/alloy) desligado explicitamente (chaves top-level), `hostpathClass.enabled: false`. SC
gerenciada por nós com `BasePath: /var/mnt/pv-data/openebs`. Namespace com PSA privileged
(sync-wave -1). Exit: só `openebs-localpv-provisioner` Running; SC `openebs-hostpath` default;
sem pods de mayastor/lvm/zfs/loki/alloy/minio.

## 4.5 Validação ponta a ponta
`kubectl apply -f test/pv-smoke.yaml` → PVC Bound; o dado materializa em
`/var/mnt/pv-data/openebs/<pvc>` no worker (disco dedicado, não no boot).
