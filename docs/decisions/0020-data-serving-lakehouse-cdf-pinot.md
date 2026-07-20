---
tipo: adr
numero: 20
titulo: Data serving realtime sobre lakehouse — Delta CDF → Redpanda → Pinot upsert
status: aceito
fases: [12]
relacionado: [runbooks/data-platform/lakehouse-spark-delta-pinot, decisions/0009-data-platform-stores]
---

# ADR-0020 — Data serving realtime sobre lakehouse (Delta CDF → Redpanda → Pinot upsert)

## Status
Aceito (validado fim-a-fim no homelab, jul/2026). POC para proposta em ambiente de
trabalho; Data API gRPC na frente do broker fica para fase futura.

## Contexto

Validar a arquitetura *lakehouse como fonte de verdade + serving OLAP realtime por
CDC* antes de propô-la profissionalmente: uma tabela operacional mutável
(`accounts`, MERGE contínuo com hot keys Zipfianas) no Delta Lake sobre Garage,
servida com latência de segundos por um store OLAP de queries user-facing.

Fundamentos que restringem o desenho:

1. **CDF é sobre mutação, não sobre latência.** A matriz de decisão: tabela
   append-only nunca precisa de CDF (mesmo em realtime, `readStream` puro entrega
   appends); tabela mutável servida por cron também não (o job lê um snapshot —
   garantia de versão do Delta — e reconstrói). CDF é obrigatório em exatamente
   um quadrante: **mutável + near-realtime**. Nos demais, é no máximo otimização
   batch incremental (`table_changes(v1, v2)`).
2. **Delta OSS em S3-compatível não suporta multi-writer** (sem put-if-absent;
   S3DynamoDBLogStore exige DynamoDB). Corrida entre writers corrompe o log.
3. **Upsert do Pinot é realtime-only** — não existe perna offline/híbrida para
   tabela upsert. Toda carga, inclusive a inicial, entra pelo tópico.
4. A property `delta.deletedFileRetentionDuration` é o **guard de leitura** do
   CDF (a promessa); o `VACUUM RETAIN` é a prática. Desalinhados, o consumidor
   CDF quebra em resume mesmo com arquivos presentes.

## Decisão

Pipeline: gerador Spark (único writer, MERGE + OPTIMIZE/VACUUM in-process) →
Delta CDF → job Structured Streaming → Redpanda (`accounts.cdf`, key=PK, 3
partições, 24h) → Pinot realtime upsert (comparison `_commit_version`,
`deleteRecordColumn=deleted`, retenção 3d, deep store no Garage, compaction via
Minion). Hidratação por job batch one-shot que produz o snapshot@V no mesmo
tópico carimbado com `_commit_version=V`.

Decisões subordinadas e racionais:

| Decisão | Racional |
|---|---|
| Spark **4.1.1** pinado (nunca 4.1.2+) | Delta 4.2.0 declara `pyspark<=4.1.1` (delta-io#6888); Spark muda construtor interno do Parquet em *patch releases* e quebra o Delta no caminho do checkpoint. Teto de compatibilidade mora no metadata do delta-spark. |
| Manutenção (OPTIMIZE/VACUUM) dentro do loop do gerador | Single-writer por construção (contexto 2). Write amplification do MERGE torna manutenção obrigatória, não higiene. Migrations idem: rodam com o gerador suspenso. |
| VACUUM/property = **6h**, casados | Teto de downtime tolerável do streaming; margem p/ kill/resume e pausas de teste; ~7GB flutuantes dentro do budget (~35GB total). |
| Deletes **uniformes**, updates Zipf | Deletes Zipfianos extinguem a cabeça da distribuição (hot key morta ⇒ updates viram no-op) e o CDF só observa a cauda — inutiliza o estresse de upsert quente. |
| Delete viaja como registro com `deleted=true` (não tombstone null) | `deleteRecordColumn` do Pinot exige campo em registro parseável; tombstone null é para tópicos compactados. `key=PK` preserva ordem por chave. |
| Comparison column = `_commit_version` | Monotônico por construção do log Delta ⇒ resolve interleaving hidratação×stream **sem coordenação** (mudança pós-snapshot tem versão > V sempre). Vencedores do hydrate = contas com último toque ≤ V (não apenas as ausentes do tópico) — a aritmética fechou exata na validação. |
| Deep store no bucket `pinot` do Garage | Server volta do zero re-baixando selados (validado por kill/resume); `S3PinotFS` tem `forcePathStyle(true)` hardcoded — Garage-compatível sem gambiarra. Credencial via env (chain do SDK), nunca em config (config vaza na API/UI). |
| Pinot inteiro no `worker-4-compute` | A RAM está lá e o incidente de page faults provou que S3 pesado é vizinho hostil do Garage. Concessão de homelab: em produção, serving (stateful, latência) separa de batch compute. |
| Minion + `UpsertCompactionTask` (com `enableSnapshot`) | Cabeça Zipf invalida ~576k linhas/dia em segmentos selados; sem compaction o budget de 3d é fictício. |
| Código dos jobs como pacote instalado na imagem (`lakehouse-jobs`) | ConfigMap de scripts serviu ao bootstrap; produção exige testes, versionamento acoplado (tag=código) e reuso. Migrations = runner Flyway-like com estado em Delta (`_meta/schema_migrations`); dbt descartado (tabela operacional não é model derivado de SELECT; dbt-spark exigiria conexão Spark permanente). |
| Schema/tabela do Pinot: JSON no repo + recipe `just` | Sem CRD oficial; objetos vivem no ZK via REST. JSON fora de `manifests/` (Argo os aplicaria como recurso k8s). Teto de GitOps da ferramenta, documentado. |

## Consequências

**Positivas**: paridade exata Delta↔Pinot em alvo móvel (lag fim-a-fim sub-round);
sobrevivência validada a kill/resume de streaming e server (checkpoint no Garage;
re-download do deep store + rebuild do mapa de upsert); at-least-once no
transporte tornado inócuo pela idempotência por chave no destino; hidratação e
replay sem janela de manutenção.

**Negativas/dívidas**: (a) senha SASL visível na API/UI do Pinot (injetada no
apply, placeholder no Git) — produção pede secret provider; (b) GitOps parcial
para objetos do Pinot; (c) single-writer é restrição real — multi-writer exige
DynamoDB LogStore ou catálogo com commit coordinator; (d) HA não exercitado
(réplicas 1, RF 1); (e) lag do Pinot não aparece em consumer group (assign
manual, offsets no metadata de segmento) — monitorar pela API; (f) downtime do
streaming > 6h exige recriar checkpoint + hydrate.

Incidentes e diagnósticos operacionais desta arquitetura: ver runbook
`runbooks/data-platform/lakehouse-spark-delta-pinot.md`.
