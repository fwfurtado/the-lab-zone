---
tipo: setup
fase: 8
titulo: Analytics / ELT — ClickHouse + dbt + goose via Argo Workflows
relacionado: [decisions/0013-argo-workflows-git-artifact-elt]
---

# Setup Fase 8 — Analytics / ELT

Plataforma analítica sobre os dados de LLM do Langfuse (custo/latência/erros). Batch ELT
reusando a ClickHouse da Fase 6, orquestrado por Argo Workflows, migrations via goose e
transformações via dbt. Imagens genéricas + código por git artifact.

## Estado final da app `dbt-analytics`
`apps/data/dbt-analytics/` com: `chart/` (1º chart local do repo — Chart/values, templates de
ExternalSecret, CronWorkflow `analytics-elt` com `schedules: [6h]`, VMRule `AnalyticsEltFailed`
com nome COM prefixo, e workflow-templates `clickhouse-migrate` + `analytics-etl`);
`migrations/clickhouse/` (goose, git artifact); `dbt/` (projeto, git artifact, seeds CSV puro sob
`_seeds.yml`, models staging/intermediate/marts com subselect anti-colisão); `workflows/`
(run-once, fora do `source.path`). Imagens `goose-runner`/`dbt-runner` (pin por digest).

## Validação (run de fechamento)
`dbt build` → PASS=18, ERROR=0 (5 views, 4 tables, 2 seeds, 7 tests). `mart_rag_cost_daily` com
reprecificação funcionando (retrieval free, geração precificada via gateway).

## RAG×custo (Nível B)
3 projetos no Langfuse logam a mesma chamada sem elo cross-projeto → custo = só gateway (ledger
LiteLLM); o mart reprecifica os tokens do rag pela taxa $/token do gateway, casando por
`model_canonical`. Evita double-count; custo é estimado (taxa blended). Atribuição exata exigiria
propagar um id único Open WebUI→LightRAG→LiteLLM (mudança nas apps, não no pipeline).
