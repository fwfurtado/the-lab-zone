---
tipo: adr
numero: 7
titulo: Storage LocalPV hostpath em disco dedicado por worker (anti fake-HA)
status: aceito
fases: [4]
relacionado: [runbooks/storage]
---

# ADR-0007 — LocalPV hostpath, Mayastor descartado

## Status
Aceito (Fase 4).

## Contexto
O cluster precisa de tier quente RWO pros stores stateful da Fase 6. Mayastor (replicated
PV) era a alternativa "HA".

## Decisão
**LocalPV hostpath**, num **disco dedicado por worker** (`virtio1` → `/var/mnt/pv-data`),
separado do disco de OS/efêmero. StorageClass gerenciada por nós (não pelo chart), default,
`WaitForFirstConsumer`. Mayastor **descartado**.

## Porquê
Replicar entre worker-1/2 no mesmo NVMe físico do T630 único é **fake-HA** — não sobrevive à
falha que importa (o host). Durabilidade fica no nível da app (pgBackRest, snapshot Qdrant →
Garage → B2). Disco dedicado isola IO real pro tier quente (bancos com fsync pesado).

## Consequências
- Layout de disco é responsabilidade do OS (Talos `UserVolumeConfig`), não do cluster —
  ArgoCD nunca encosta.
- O stack de logging do Mayastor (loki/alloy/minio, chaves top-level) precisa ser desligado
  explicitamente (ver runbook storage).
- Tier RWX (democratic-csi → NFS do TrueNAS) fica adiado até o primeiro workload que precise.
- `backup = false` no vzdump do disco de PV (DR é app-level, não snapshot crash-consistent).
