---
tipo: runbook
componente: argo-workflows
tags: [argo-workflows, cronworkflow, templateref, git-artifact, dbt, goose, clickhouse, metrics, https]
fases: [8]
relacionado: [runbooks/data-platform, runbooks/observability, runbooks/network-policies]
---

# Argo Workflows: ELT, ClickHouse/dbt/goose e métricas

Pipeline batch (migrations goose + dbt) orquestrado por Argo Workflows, imagens genéricas +
código por git artifact.

## Workflow com `generateName` não é GitOps

**Sintoma:** ArgoCD falha o sync (server-side apply) num objeto com `generateName`.
**Causa:** `apply` precisa de `name` fixo pra calcular o diff; um `Workflow` one-shot usa
`generateName`.
**Diagnóstico:** o `Workflow` de teste vazou pra um path sincronizado (`chart/templates/`).
**Fix:** só `WorkflowTemplate`/`CronWorkflow` (nome fixo) vão pro Git. `Workflow` one-shot fica
em `workflows/` (fora do `source.path`) e roda imperativo (`kubectl create -f` / `argo submit
--from workflowtemplate/...`).
**Lição:** GitOps = nome fixo. `generateName` = imperativo. Não existe "Workflow one-shot
versionado".

## `templateRef` não herda `spec.volumes`

**Sintoma:** `volume 'migrations' not found in workflow spec` no step `goose-up`, **só** quando
rodado pela DAG; standalone funcionava.
**Causa:** `workflowTemplateRef` (no Workflow) copia o spec inteiro da WT (com volumes);
`templateRef` (dentro de DAG/steps) empresta **só o template**, não campos spec-level como
`volumes`.
**Fix imediato:** declarar `spec.volumes` também na DAG. **Fix definitivo:** migrar as migrations
de ConfigMap pra **git artifact** — `inputs.artifacts` É parte do template, herdado via
`templateRef`. Matou o acoplamento e o volume de vez.
**Lição:** o que é spec-level não viaja por `templateRef`; `inputs.artifacts` viaja. Git artifact
> volume pra qualquer coisa chamada por `templateRef`. (Contraste: o `emptyDir` de um
`containerSet` fica em `spec.volumes` do WorkflowTemplate e **É** herdado pelo
`workflowTemplateRef` do CronWorkflow — ver `runbooks/backup-dr/`.)

## Argo 3.6+/v4: breaking changes de schema

**Sintoma:** `spec.schedules: Required value` (CronWorkflow) e `spec.metrics.prometheus[0].
gauge.realtime: Required value` (WorkflowTemplate).
**Causa:** a 3.6 trocou `schedule` (singular) por `schedules` (lista) e tornou `gauge.realtime`
obrigatório.
**Fix:** `schedules: [ "<cron>" ]`; `realtime: false` no gauge (emite no fim do run). Counter não
precisa.

## Métricas custom ganham prefixo `argo_workflows_`

**Sintoma:** VMRule/queries com `analytics_elt_runs_total` nunca casam, mesmo com a métrica
existindo.
**Causa:** o controller prefixa as métricas custom com `argo_workflows_`.
**Fix:** usar o nome **com prefixo** (`argo_workflows_analytics_elt_runs_total`) no `expr` da
VMRule e em painéis.
**Lição:** confirmar o nome emitido no `/metrics`, não assumir o nome declarado.

## Endpoint de métricas do Argo 3.6+ é HTTPS por default

**Sintoma:** `curl http://<controller>:9090/metrics` vazio, apesar da porta existir.
**Causa:** `metricsConfig.secure` passou a ter default **true** na 3.6 → endpoint HTTPS com cert
self-signed.
**Fix:** `metricsConfig.secure: false` (configmap) + **restart do controller** (não faz
hot-reload do metricsConfig). VMPodScrape volta pra `scheme: http`. (Alternativa: `scheme: https`
+ `tlsConfig.insecureSkipVerify`.)

## VMPodScrape cross-namespace precisa de `namespaceSelector`

**Sintoma:** o target nunca aparece no vmagent, mesmo com o VMPodScrape `operational` e a métrica
presente.
**Causa:** VMPodScrape em `observability`, sem `namespaceSelector`, só procura pods na própria ns;
o controller está em `argo-workflows`.
**Fix:** `spec.namespaceSelector.matchNames: [argo-workflows]`.
**Lição:** scrape cross-namespace exige `namespaceSelector` explícito; `operational` ≠ target
ativo.

## vmagent vs VMSingle pra query

**Sintoma:** `unsupported path requested: "/api/v1/query"` na 8429; depois, `result: []`.
**Causa:** port-forward no **vmagent** (só ingest/buffer) em vez do **VMSingle** (8428, o
storage).
**Fix:** query no VMSingle. **Lição:** vmagent não é o storage.

## ClickHouse / dbt / goose

- **CHI da Altinity não cria database declarativamente** → step `ensure-db` no Workflow (`curl`
  no 8123, `CREATE DATABASE IF NOT EXISTS`), fora do goose (a version table do goose mora nele).
- **`singleBranch: true` no git artifact** exige branch explícito (`single branch mode without a
  branch specified`). Remover `singleBranch` — `depth: 1` já dá o clone raso.
- **Seed do dbt é CSV puro** (agate trata `#` como dado, não comentário) → CSV sem comentário;
  doc vai na `description` do schema yml.
- **Seed se documenta sob `seeds:`, não `models:`** (senão testes do seed ficam skipados).
- **Mudar coluna de seed exige recriar a tabela** (`dbt seed` faz INSERT, não ALTER) →
  `DROP TABLE` ou `dbt build --full-refresh` **uma vez**; steady-state segue normal.
- **ClickHouse dropa coluna homônima em JOIN** (`UNKNOWN_IDENTIFIER ... Maybe you meant`) →
  renomear a colidente do lado direito num subselect (`project_id as pd_project_id`); usar
  colunas do lado esquerdo e, da direita, só nomes únicos. Evitar `*` em models com JOIN.

## Lição transversal

Migrar `Job → Workflow` muda três coisas com consequência de rede: **identidade** (pod labels →
`runbooks/network-policies/`), **caminho dos logs** (`archiveLogs` → Garage:3900) e **modelo de
retry**. Git artifact > ConfigMap/volume pra árvore que cresce e pra herança via `templateRef`.
3.6 mudou defaults (schedules, gauge.realtime, métricas HTTPS) — validar breaking changes de CRD
antes de assumir compat.
