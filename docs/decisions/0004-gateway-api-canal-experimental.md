---
tipo: adr
numero: 4
titulo: Gateway API no canal experimental, CRDs vendorizados
status: aceito
fases: [3]
---

# ADR-0004 — Gateway API canal experimental, CRDs vendorizados

## Status
Aceito (Fase 3).

## Contexto
O Cilium 1.19 serve o Gateway API. Há dois canais de CRDs (standard e experimental).

## Decisão
Usar o canal **experimental** (v1.5.1), com os 9 CRDs **vendorizados** no repo
(`apps/core/gateway-api-crds/manifests/`). Não vendorizar o `kustomization.yaml`, a VAP
`safe-upgrades`, nem os CRDs de mesh.

## Porquê
O Cilium 1.19 indexa `TLSRoute` em `gateway.networking.k8s.io/v1alpha2`, que **só existe no
canal experimental**. O standard, mesmo na v1.5.1, traz `TLSRoute` só em `v1` — e o field
indexer do operator morre sem o `v1alpha2` (CrashLoop). Vendorizar evita o timeout de clone
do repo gigante e fixa a versão.

## Consequências
- A VAP `safe-upgrades` (que bloqueia standard→experimental) **não** é versionada — senão
  reintroduz o bloqueio na reconciliação do ArgoCD (ver runbook gateway-dns).
- Upgrades do Cilium exigem reverificar a versão de `TLSRoute` exigida pelo field indexer.
