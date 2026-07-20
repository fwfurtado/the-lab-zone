---
tipo: runbook
componente: data-platform
tags: [spark, delta, cdf, redpanda, pinot, upsert, spark-operator, kafka, garage, lakehouse, hydrate, vacuum, minion]
fases: [12]
relacionado: [decisions/0020-data-serving-lakehouse-cdf-pinot, runbooks/data-platform/spark-garage-victoriametrics-memory-2026-07-20]
---

# Lakehouse serving: Spark, Delta CDF, Redpanda e Pinot

Incidentes da construção do pipeline Delta CDF → Redpanda → Pinot upsert
(ADR-0020). Arquitetura e racionais no ADR; aqui, sintoma → causa → fix.
O incidente de page faults Garage×Spark tem runbook próprio
(`spark-garage-victoriametrics-memory-2026-07-20.md`).

## Spark/Delta — driver morre a cada ~10min com NoSuchMethodError

**Sintoma:** `NoSuchMethodError: ParquetToSparkSchemaConverter.<init>(boolean×N)`
periódico (~10 commits); MERGEs funcionam entre as mortes.
**Causa:** Delta 4.2.0 compilado contra Spark 4.1.1 rodando em 4.1.2 — o Spark
muda esse construtor interno em *patch releases* (4.0.0→4.0.1 e 4.1.1→4.1.2);
o caminho quebrado é o checkpoint do `_delta_log` (a cada 10 commits). Delta
declara `pyspark>=4.0.1,<=4.1.1` no metadata (delta-io#6888).
**Diagnóstico:** `javap -v` no jar da imagem conta os booleans da chamada
compilada — bytecode é fonte; contagem em log renderizado quebra linha e engana.
**Fix:** imagem base pinada em `spark:4.1.1`; comentário-sentinela no Dockerfile.
**Lição:** bump de patch do Spark exige conferir o teto de pyspark no metadata
do delta-spark vigente.

## Spark/Delta — CANNOT_INFER_SCHEMA_FOR_TYPE str_

**Sintoma:** driver crasha no primeiro round; operator mascara como restart loop.
**Causa:** `numpy.str_` em tupla do `createDataFrame` (um `str()` esquecido).
**Fix:** converter tipos numpy na borda; reproduzido e validado com PySpark
local no sandbox antes do patch.
**Lição:** pods de driver são DELETADOS no retry do operator (`Restart Count: 0`
engana); o traceback sobrevive no VictoriaLogs
(`k8s.pod.name: "x" ~"(?i)Error"`) e no status da SparkApplication.

## Spark/Delta — executor OOMKilled (137) no meio do MERGE

**Sintoma:** `CHECKPOINT_RDD_BLOCK_ID_NOT_FOUND` no driver; executor com
`ExitCode: 137, OOMKilled` nos events; sistema se auto-recupera (Delta tem retry
para perda da fonte materializada do MERGE).
**Causa:** excesso de memória **nativa** (Netty, buffers Parquet, fonte
materializada via localCheckpoint) — heap capado não estoura cgroup sozinho.
**Fix:** subir `memoryOverhead` do executor, não `memory`.
**Lição:** 137 = morte por cgroup = fatia nativa; o driver PySpark já ganha 40%
de overhead automático, o executor não.

## Spark/Delta — CDF recusa leitura (DELTA_UNSUPPORTED_TIME_TRAVEL…)

**Sintoma:** `Cannot time travel beyond deletedFileRetentionDuration (1 HOURS)`.
**Causa:** property da tabela (guard de leitura, a *promessa*) desalinhada do
`VACUUM RETAIN` (a *prática*) — bootstrap fixou 1h, gerador vacuum 6h.
**Fix:** `ALTER TABLE SET TBLPROPERTIES` com o gerador **suspenso**
(single-writer vale pra DDL) + bootstrap corrigido p/ recriações.
**Lição:** consumidor CDF parado além da property quebra em resume mesmo com os
arquivos presentes; as duas retenções andam juntas.

## Spark/Delta — distribuição Zipf "sem cabeça" no CDF

**Sintoma:** top-N de updates sem os ids quentes; metade dos updates virando
no-op (postimages ≪ tentados).
**Causa:** deletes amostrando da mesma cabeça Zipf — hot keys extintas nos
primeiros rounds; update em chave morta = no-op por design.
**Fix:** deletes uniformes, updates Zipf; tabela sintética recriada (fix impede
novas extinções, não ressuscita).
**Lição:** valide a distribuição OBSERVADA no dado, não a intenção do código; e
o dedup pré-MERGE limita 1 op/chave/round ⇒ a assinatura Zipf correta é cabeça
*saturada* em `updates = nº de rounds`, nunca "milhares vs unidades".

## Spark 4 — PYSPARK_DRIVER_PYTHON=jupyter quebrou

**Sintoma:** Jupyter sobe em localhost ignorando opts; warning
`Unrecognized alias: 'c'`; probe em connection refused.
**Causa:** `bin/pyspark` do Spark 4 executa `$PYSPARK_DRIVER_PYTHON -c
"...spark_connect_mode..."` p/ detectar connect mode — com jupyter, isso sobe um
servidor acidental e bloqueia o launch no command substitution.
**Fix:** jupyter-lab direto; PYTHONPATH pro pyspark do `/opt/spark` (nunca pip
pyspark — jars divergem); `spark.master` em `spark-defaults.conf` via
`SPARK_CONF_DIR`; sessão criada no kernel (startup do IPython).

## Jupyter — startup do IPython ignorado

**Sintoma:** `spark` indefinido no kernel apesar do ConfigMap montado.
**Causa:** mount de ConfigMap em caminho profundo
(`~/.ipython/profile_default/startup`) faz o kubelet criar dirs-pai como
**root**; IPython (uid 185) sem escrita no profile cai em perfil temporário.
**Fix:** montar em `/etc/ipython-startup` + `mkdir && cp` no boot antes do
`exec jupyter-lab` (HOME é gravável pelo chown do Dockerfile).

## Jupyter — jupyterlab-sql-editor "não funciona"

**Sintoma:** `%%sparksql` inexistente após instalar `jupyterlab-sql-editor[all]`.
**Causa dupla:** o extra `[all]` instala **pyspark do PyPI** (segundo Spark com
jars próprios divergindo do `/opt/spark`); e o magic exige
`%load_ext jupyterlab_sql_editor.ipython_magic.sparksql` — não se registra
sozinho.
**Fix:** instalar sem extra; load_ext no startup do IPython.

## spark-operator — SUBMISSION_FAILED coletivo após bump de imagem

**Sintoma:** todos os apps falham simultaneamente; "erro" é output truncado de
submit pendurado; `BlockedThreadChecker` em cascata; fabric8 com timeout pro API
server e hint enganoso de RBAC; stacktrace bloqueada em `<clinit>` de classe SSL.
**Causa:** bump de imagem compartilhada = Argo re-submete N apps de uma vez = N
JVMs de spark-submit no pod do operator com cpu limit 500m ⇒ throttling de
cgroup faminta até class-init.
**Fix:** recuperação por serialização (suspend N-1, liberar escalonado);
estrutural: requests 500m/1Gi, **sem CPU limit** (burst de JVM curta é o pior
caso de throttle), memory limit 2Gi.
**Lição:** o hint `kubectl auth can-i` do fabric8 aparece em QUALQUER falha de
conexão — red herring.

## Redpanda — User CR rejeitado na ACL de cluster (2×)

**Sintoma:** primeiro "name must not be specified", depois "name: Required".
**Causa:** contrato real na regra CEL do CRD: `name` é estruturalmente
obrigatório mas DEVE ser `""` para type cluster/registry; sem patternType.
**Fix:** `name: ""`.
**Lição:** schema de CRD ≠ contrato completo — ler `x-kubernetes-validations`
junto. Vale também para labels: os pods Spark usam `spark-role`
(driver/executor), não `app.kubernetes.io/name`.

## Pinot — apply-table pendura sem erro; TimeoutException no AdminClient

**Sintoma:** POST /tables trava; log do controller com
`TimeoutException` em `topicExists`, sem erro de auth/SSL; Pinot faz rollback
completo da tabela.
**Causa:** props `stream.kafka.consumer.prop.security.*` **silenciosamente
filtradas** pelo plugin kafka30 (o builder faz putAll do map cru e filtra por
nomes VÁLIDOS de config Kafka) ⇒ AdminClient plaintext contra listener TLS =
timeout mudo.
**Fix:** props de segurança SEM prefixo, direto no streamConfigMap
(`security.protocol`, `sasl.jaas.config`, `ssl.truststore.*`);
`auto.offset.reset` prefixado FICA (parseado p/ offset criteria).
**Lição:** timeout mudo em Kafka+TLS = suspeite de plaintext-vs-TLS antes de
rede; POST /tables valida o stream INLINE — sempre `--max-time` no curl.

## Pinot — "fix não resolveu" (config nova ignorada)

**Sintoma:** ConfigMap correto no cluster, processo rodando config velha; e
value duplicado com vírgula (`/var/pinot/...,s3://pinot/deepstore`).
**Causa dupla:** `automaticReload` é false por default no chart (mudança de
ConfigMap não recicla pod; Pinot lê config no boot — o log era o dump antigo); e
setar via `extra.configs` o que o chart expõe como value de 1ª classe duplica a
chave (o parser concatena com vírgula).
**Fix:** `automaticReload.enabled: true` (checksum annotation) nos StatefulSets;
valores de 1ª classe sempre pelo value do chart.
**Lição:** sem reload automático, todo `Synced` do Argo é mentira operacional
para configs de boot.

## Pinot — UpsertCompaction "não fez nada"

**Sintoma:** trigger manual responde `{"UpsertCompactionTask":""}` — vazio.
**Causa:** task name vazio = zero tasks geradas (não é falha): `bufferTimePeriod`
exclui segmentos selados há menos de 2h, e `enableSnapshot` recém-ligado ainda
não produziu validDocIds p/ os antigos.
**Fix:** esperar o buffer; re-trigger; validar pelo `df` do server caindo e
`count(*)` inalterado (compaction remove obsoletos, nunca vencedores).

## Pinot — verificações estruturais que evitaram incidentes

- `S3PinotFS` (1.5.1) tem `forcePathStyle(true)` **hardcoded** e chave
  `disableAcl` — Garage funciona sem config extra (verificado no fonte antes do
  deploy; SDK v2 default seria virtual-host e quebraria).
- Consumer `lowlevel` faz assign manual **sem consumer group**: offsets no
  metadata dos segmentos ⇒ sem ACL de group, e lag não aparece em `rpk group` —
  monitorar pela API do Pinot.
- Drift eterno de StatefulSet no Argo: API server normaliza
  `volumeClaimTemplates` (remove apiVersion/kind) ⇒ `ignoreDifferences` com
  jqPathExpressions (sem `name` cobre todos os STS do app).

## ArgoCD/CI — armadilhas de estrutura

**Subdirs em manifests/:** source de diretório NÃO é recursivo por default; com
prune, mover YAMLs p/ subdirs sem `directory.recurse: true` deleta todos os
recursos. Mesmo commit, atomicamente.

**Matrix de build sem ordem:** imagem base + dependente no mesmo push quebra o
build do dependente (spark-jupyter FROM spark-delta). Ou `needs:` encadeado, ou
pushes separados; a tag real que o semver-bot atribui é a fonte, não a prevista.

**JSON de tabela Pinot em manifests/:** o Argo aplicaria como recurso k8s —
objetos de API do Pinot vivem em `apps/data/pinot/tables/` + recipe `just`.

## rpk — leitura de janelas no tópico

`--offset -N` é POR PARTIÇÃO (temos 3); `-n` é teto global. Um commit do gerador
≈ 2.600 mensagens no tópico — janela menor que isso mostra "uma versão só".
Regra: `offset_por_partição ≈ (commits_desejados × 2600) / 3`. Continuidade de
`_commit_version` sem buracos atravessando um kill = zero perda (duplicata é
at-least-once fazendo o trabalho; buraco reprova).
