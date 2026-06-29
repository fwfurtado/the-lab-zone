---
tipo: adr
numero: 9
titulo: Plataforma de dados — Garage, CNPG, Valkey, ClickHouse, Qdrant, Memgraph
status: aceito
fases: [6]
relacionado: [runbooks/data-platform]
---

# ADR-0009 — Escolha dos stores stateful

## Status
Aceito (Fase 6).

## Contexto
Provisionar todos os backends stateful vazios e validados antes de qualquer app de negócio,
pra que falha de store nunca se confunda com falha de app.

## Decisão
| Papel | Escolha | Porquê |
|---|---|---|
| Object storage | **Garage** | S3-compatible, Rust, single-node honesto, sem dependências externas |
| PostgreSQL | **CNPG + PG18** | Operator maduro, WAL→Garage via barman, PITR real |
| Cache/fila | **Valkey** | Redis-compatible, licença limpa, `noeviction` pra queue do Langfuse |
| Analytics/eventos | **ClickHouse (Altinity operator)** | Backend nativo do Langfuse, reusado na Fase 8 |
| Vector store | **Qdrant** | Pipeline RAG (LightRAG, Fase 7) |
| Graph store | **Memgraph** | LightRAG híbrido (grafo + vetor) |

Operators (CNPG, ClickHouse) vão pro AppProject `core`; workloads pro AppProject `data`.

## Consequências
- Garage tem quirks de S3 (alias global, `region=garage`, path-style, world-readable
  secrets) — ver runbook data-platform.
- Memgraph métricas exigem Enterprise (sem dashboard na community).
- Object storage único (Garage) é tier on-site; DR vai pro B2 (ADR-0014).
