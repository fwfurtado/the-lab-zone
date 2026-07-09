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

## `AUTHENTICATION_FAILED` com a senha certa e goose dizendo "no migrations to run"

**Sintoma:** `dbt-build` falha com `Code: 516 ... analytics: Authentication failed: password is
incorrect, or there is no user with such name`, mesmo com a senha do secret correta (sem
newline: último byte `6e`, não `0a`). O step `goose-up` acima passou verde:
`goose: no migrations to run. current version: 20260619173523`.

**Causa:** o usuário **não existia**. A segunda metade da mensagem do ClickHouse é a
verdadeira (*"or there is no user with such name"*). A migration que o criava
(`CREATE USER IF NOT EXISTS analytics`) estava registrada como aplicada em
`analytics.goose_db_version`, mas o usuário havia sumido. Os dois estados têm **ciclos de vida
distintos**: a tabela do goose é DADO (database `analytics`, no PVC); o usuário criado por SQL
mora no **access storage** do ClickHouse (`system.users.storage='disk'`, diretório à parte).
Perdido o access storage (recreate/restore parcial), o registro do goose sobrevive, o goose pula
a migration e ninguém recria o usuário. Assinatura do bug: `analytics` era o **único** usuário
`disk` — `admin`, `langfuse`, `backup`, `default` são `users_xml` (reconciliados pelo operator a
cada boot) e sobreviveram.

**Diagnóstico:**
1. **`AUTHENTICATION_FAILED` prova que o servidor está vivo** (erro de aplicação, não timeout).
   Se o CH estivesse fora, o dbt daria `Could not connect`.
2. Isolar auth de rede — `kubectl exec` **dentro do pod do CH** (não passa pelo CNP):
   `clickhouse-client --user analytics --password "$PW" --query "SELECT currentUser()"`.
3. A pergunta que fecha o caso:
   `SELECT name, auth_type, storage FROM system.users` — se `analytics` não aparece, não é senha.
4. `SELECT * FROM analytics.goose_db_version` mostra a migration "aplicada" → **drift**.

**Armadilha do diagnóstico:** testar com um pod avulso (`kubectl run ... --image=curlimages/curl`)
dá `Could not connect ... after 133s` e sugere ClickHouse morto. É o `clickhouse-default-deny-ingress`
dropando: a `8123` só é liberada pra `langfuse` (ns `ai`) e `analytics-etl` (ns `data`). Pod sem
esses labels não passa. Use `--labels='app.kubernetes.io/name=analytics-etl'` ou `exec` no pod.

**Fix imediato** (destrava o ETL; `sha256_password BY` recebe a senha em **texto claro** — o CH
calcula o hash. Só `sha256_hash BY` recebe hex):
```
CREATE USER IF NOT EXISTS analytics IDENTIFIED WITH sha256_password BY '<senha>';
GRANT SELECT ON `default`.* TO analytics;
GRANT ALL ON analytics.* TO analytics;
GRANT SELECT ON system.* TO analytics;
```

**Fix definitivo:** usuário, rede e grants viraram declarativos no `ClickHouseInstallation`
(`files."users.d/custom-users.xml"`, `password_sha256_hex from_env`, hash via ESO/`sha256sum` do
mesmo item 1Password que o dbt lê em claro). A migration virou no-op. Ao migrar, **dropar antes o
usuário SQL** (`DROP USER IF EXISTS analytics`): o ClickHouse proíbe gerenciar a mesma entidade de
acesso por XML e por SQL ao mesmo tempo.

**Lição:** `CREATE USER IF NOT EXISTS` em migration é idempotente na **existência**, não no
**estado** — nunca converge rotação de senha. E RBAC criado por SQL vive fora do ciclo de vida do
operator: sobrevive diferente do dado, e o versionador (goose) não enxerga a divergência. Num
cluster gerenciado por operator, RBAC é **config declarativa**, não migration. Quando a mensagem
de erro tem um "ou", leia a segunda metade.

## Lição transversal

Migrar `Job → Workflow` muda três coisas com consequência de rede: **identidade** (pod labels →
`runbooks/network-policies/`), **caminho dos logs** (`archiveLogs` → Garage:3900) e **modelo de
retry**. Git artifact > ConfigMap/volume pra árvore que cresce e pra herança via `templateRef`.
3.6 mudou defaults (schedules, gauge.realtime, métricas HTTPS) — validar breaking changes de CRD
antes de assumir compat.
