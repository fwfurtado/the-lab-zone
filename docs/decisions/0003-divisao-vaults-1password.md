---
tipo: adr
numero: 3
titulo: Divisão de vaults no 1Password (homelab=bootstrap, the-lab-zone=runtime)
status: aceito
fases: [2]
---

# ADR-0003 — Divisão de vaults no 1Password

## Status
Aceito (Fase 2).

## Contexto
Secrets têm dois consumidores muito diferentes: o operador humano (durante bootstrap/DR) e
o cluster (em runtime, via ESO).

## Decisão
Dois vaults com papéis distintos:
- **`homelab`** — secrets de bootstrap/humano (age, tokens TF, credenciais do Connect).
  Acessado pelo operador via `op` CLI.
- **`the-lab-zone`** — secrets consumidos pelo cluster em runtime. Acessado pelo ESO, via
  Connect server.

O Connect server tem acesso **apenas** ao vault `the-lab-zone`.

## Consequências
- Um item no vault errado é invisível pro ESO (causa raiz de classe de incidente — ver
  runbook secrets-eso).
- O blast radius do Connect server (que roda no cluster) é limitado ao vault de runtime; os
  secrets de bootstrap/humano nunca passam por ele.
