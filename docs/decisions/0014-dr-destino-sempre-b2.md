---
tipo: adr
numero: 14
titulo: Destino de DR é sempre B2 (off-site); Garage é tier on-site
status: aceito
fases: [10]
relacionado: [runbooks/backup-dr]
---

# ADR-0014 — Destino de DR sempre off-site (B2)

## Status
Aceito (Fase 10).

## Contexto
Até a Fase 10, todo backup stateful vivia só no Garage (single-node, no próprio T630). "O
T630 morreu" = perda total.

## Decisão
**Destino de DR é sempre B2** (off-site, fora do T630). Garage é tier on-site.
- **Espelho Garage→B2** via `rclone` em CronWorkflow (Argo), layout 1:1 (restore só troca
  endpoint). `copy` pros append-only, `sync` só pro langfuse (dado vivo).
- **Velero** pros objetos K8s + FSB (Kopia, sem VolumeSnapshot — LocalPV hostpath não tem
  CSI snapshot). FSB é opt-in; nunca PV de banco com backup nativo.
- **CNPG backup** via Barman Cloud Plugin (a imagem `-standard` não tem barman; in-tree morre
  no 1.30). Cluster vira manifesto cru (o chart não expressa `.spec.plugins`).
- App keys B2 criadas no console → 1Password (one-way `op→repo`, sem key material no state).

## Consequências
- RPO off-site do Postgres = intervalo do cron (2h). On-site cobre RPO curto; B2 cobre "o
  T630 morreu".
- Lição transversal: **status verde é promessa; a prova é ler o destino** — ver runbook
  backup-dr.
