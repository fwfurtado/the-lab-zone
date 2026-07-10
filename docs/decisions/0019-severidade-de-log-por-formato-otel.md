---
tipo: adr
numero: 19
titulo: Severidade de log por formato — roteamento no filelog do OTel Collector
status: aceito
fases: [5]
relacionado: [decisions/0008-observability-victoriametrics-single]
---

# ADR-0019 — Severidade de log por formato: roteamento no filelog do OTel Collector

## Status
Aceito (Fase 5 / observabilidade). Refina o pipeline de logs do ADR-0008
(coleta via OTel `filelog` → OTLP → VictoriaLogs).

## Contexto
Todos os logs chegavam ao Grafana como `unknown` — impossível filtrar por
nível, só restava caçar pelo texto do `_msg`. A cadeia da causa:

1. O preset `logsCollection` injeta um `filelog` cujo **único** operator é
   `container` — ele desembrulha o wrapper CRI/containerd e joga o payload da
   app cru em `body`. Ninguém parseia esse payload.
2. Sem parsing, o `SeverityText`/`SeverityNumber` do OTLP nunca é setado.
3. Na ingestão OTLP, o VictoriaLogs grava severidade em `severity_text` /
   `severity_number` — e quando o collector **não** seta, materializa
   `severity_text="Unspecified"` (nunca vazio).
4. O datasource do Grafana resolve nível procurando `severity_text` primeiro;
   o valor `Unspecified` cai como `unknown`.

O diagnóstico que fecha isso: `_time:… | stats by (severity_text) count()`
mostrou `Unspecified` dominando, e `NOT severity_text:*` retornando **zero**
(o campo está presente em 100% dos logs, sempre). Ou seja, o problema nunca foi
"log sem nível" — era severidade não-setada virando um valor default que o
plugin não reconhece.

## Decisão
**Parsing e classificação no `filelog`, roteados por formato**, porque o
cluster emite logs heterogêneos (slog JSON, logfmt, ClickHouse, Tetragon,
plaintext) e um parser único é frágil. Um `router` despacha por formato; cada
ramo seta severidade explícita via `severity_parser`.

### A regra que orienta tudo: `noop` == `Unspecified` == `unknown`
Deixar um log cair no `noop` (sem tocar) **não** o deixa "neutro" — o VLS
materializa `Unspecified`, que o Grafana pinta como `unknown`. Corolário
gravado: **todo formato que quisermos classificar PRECISA passar por um
`severity_parser`.** Não existe "nível padrão implícito".

### Override do preset substitui a lista de operators
O chart faz `mustMergeOverwrite(preset, .config)`: mapas mesclam, mas **listas
são substituídas**. Ao declarar `operators`, herdamos `include`/`exclude`/
`start_at` do preset, mas **reproduzimos o operator `container`** — sem ele
perde-se o unwrap CRI e o recombine de linha parcial, e todo log vira lixo.

### logfmt: extrair só o nível, via `regex_parser`
**Não existe operator `logfmt_parser` no stanza** (uma tentativa de usá-lo
derrubou o collector no boot — ver runbook). Para logfmt (velero,
controller-runtime) só precisamos do nível pro filtro: `regex_parser` com
`(?:^|\s)level=(?P<level>\w+)`. O `key_value_parser` foi **rejeitado**: ele
quebra valor citado com espaço (`msg="a b c"` viraria três pares).

### Tetragon → `debug`, de propósito
Eventos do Tetragon (namespace `tetragon`, sidecar `export-stdout`) são
auditoria eBPF: **não têm `level`** e o payload é gigante (process tree, ns,
`arguments`). Duas decisões:
- **Opaco no `_msg`** — a rota NÃO explode o JSON em fields (evitava dupla
  gravação e poluição do field set com `process_exit.*`, `ns.*`). Consulta
  estruturada sob demanda com `| unpack_json`.
- **Carimbado `debug`** (via `add` + reuso do `severity` geral) — é o papel
  desses eventos hoje: observabilidade de runtime, não sinal acionável.
  `debug` é o balde que se filtra por padrão; tira do `unknown` sem mentir
  sobre a natureza deles. Filtra-se por `k8s.namespace.name:!="tetragon"` nas
  visões de app.

### onepassword-connect: mapear pelo **prefixo**, não pelo `level` numérico
O Connect loga `{"log_message":"(I) …","level":3,…}`. O número **não é syslog**
(3=info, 4=debug) — quirk conhecida e nunca alinhada
(https://github.com/1Password/connect/issues/44). Mapear `3→?` seria adivinhar.
A rota extrai o **prefixo `(X)`** do `log_message` (`I`=info, `D`=debug,
`W`=warn, `E`=error, `F`=fatal): a letra *é* o nível, não há o que chutar.
Detectado por `body matches "\"log_message\""` e roteado **antes** da rota JSON
genérica (senão cairia nela e o `severity_parser` gravaria o literal `"3"`).

### ClickHouse: nível entre `<>`
Formato `… [ tid ] {qid} <Debug> …`. `regex_parser` extrai `<(?P<chlevel>…)>` e
mapeia; mantém-se o preset default como rede (Debug/Error/Warning/Fatal/Trace
casam) e adicionam-se os termos não-padrão (Information/Notice/Critical/Test).

### uvicorn e outros plaintext: fix na **fonte**, não no collector
Access logs plaintext (`INFO: <ip> - "GET …"`) ficam de fora. Dava pra fazer uma
rota `regex_parser`, mas a decisão é **logar JSON na origem** quando a app é
nossa: ganha-se nível *e* method/path/status como fields, com menos config no
collector. Rota regex só para app de terceiro cujo logging não controlamos.

## Consequências
- O `unknown` residual passa a ser **honesto**: só formatos plaintext ainda não
  tratados. `Unspecified` deixa de ser "tudo" e vira "o que decidimos não
  classificar" (Tetragon é `debug`, não mais `Unspecified`).
- Classificar corretamente **revela sinal antes afogado**: erros reais (ex.
  `ERROR failed to create session-scoped backends`) que estavam perdidos em
  centenas de milhares de `unknown` viram `error` filtrável.
- O `filelog` cresce em operators (router com 5 rotas + parsers por formato). A
  ordem das rotas é semântica: Tetragon e op-connect **precedem** a rota JSON
  genérica. Um tipo de operator inválido derruba o config **inteiro** no boot
  (não degrada só aquele ramo) — validar com `otelcol-k8s validate` no CI.
- Custo separado desta fatia, a registrar: Tetragon (`enableProcessCred` +
  `enableProcessNs`) e o `<Debug>` do ClickHouse dominam o ingest do VLS.
  Agora que estão classificados, dá pra decidir com dado se vale subir o log
  level do ClickHouse e enxugar o Tetragon (`fieldFilters`) — é onde está o
  custo real de storage no T630.
