---
tipo: adr
numero: 13
titulo: Argo Workflows + git artifact para ELT (goose migrations + dbt)
status: aceito
fases: [8]
relacionado: [runbooks/argo-workflows]
---

# ADR-0013 — ELT via Argo Workflows, imagens genéricas + git artifact

## Status
Aceito (Fase 8).

## Contexto
Pipeline analítico (custo/latência/erros de LLM do Langfuse) com migrations e transformações.
Precisa de orquestração, e de uma forma de entregar "código" (migrations/projeto dbt) sem
rebuild de imagem a cada mudança.

## Decisão
- **Orquestrador:** Argo Workflows (cluster-scoped, `workflowNamespaces: [data]`).
- **Migration:** goose (não Atlas — driver ClickHouse do Atlas é pago).
- **Imagens genéricas + git artifact:** `goose-runner` e `dbt-runner` são engines puros; o
  código vem do repo por `inputs.artifacts: git:` a cada run, com `revision` pinável. Mudar
  model/seed/migration = só commit+push; mudar dependência = rebuild da imagem.
- **ConfigMap só pra arquivo plano/estático; git artifact pra árvore que cresce** (CM não
  aceita `/` na chave, colisão de basename, limite 1MB).

## Consequências
- `Workflow` com `generateName` não é GitOps (só `WorkflowTemplate`/`CronWorkflow` no Git;
  one-shot é imperativo, fora do `source.path`).
- `templateRef` não herda `spec.volumes` — git artifact resolve (é parte do template).
- Argo 3.6+ trouxe breaking changes (schedules, gauge.realtime, métricas HTTPS) — ver runbook
  argo-workflows.
