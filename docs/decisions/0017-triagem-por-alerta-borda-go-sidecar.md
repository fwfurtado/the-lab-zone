---
tipo: adr
numero: 17
titulo: Triagem disparada por alerta — borda Go como sidecar do núcleo Python
status: aceito
fases: [11]
relacionado: [decisions/0015-agentes-readonly-via-pr, decisions/0016-headroom-descartado-cap-de-contexto-proprio]
---

# ADR-0017 — Triagem disparada por alerta: borda Go como sidecar do núcleo Python

## Status
Aceito (Fase 11 / camada de agentes). Define a Fase B do agente de triagem.

## Contexto
A Fase A entregou o núcleo de triagem (Python, Pydantic AI sobre o vMCP
read-only, contrato `AnswerFn`) acionado manualmente por CLI. A Fase B liga o
Alertmanager ao núcleo: alerta firing → webhook → triagem automática.

O núcleo não deve receber o Alertmanager diretamente: o processo Python longevo
guarda o `Assistant` singleton e a sessão MCP, e as responsabilidades de borda
(deduplicação, coalescing, backpressure, retry) são um domínio separado — e um
domínio onde Go é a ferramenta certa (binário estático, concorrência barata,
custo de memória irrisório).

Três fronteiras foram avaliadas:

a) **Dois Deployments + HTTP via Service** — flexível, mas cria uma porta de
   rede real para o núcleo: Service, CNP própria, mais um par na auditoria de
   políticas, e versionamento em dois rollouts.
b) **Subprocess (Go executa a CLI Python)** — perde o singleton e a sessão MCP
   (custo por triagem), memória por processo, imagem híbrida Go+Python, e o
   núcleo fica sem /metrics próprio.
c) **Sidecar no mesmo pod** — núcleo escuta em `127.0.0.1`; a fronteira HTTP
   existe (contrato limpo, migração barata para (a)), mas não atravessa a rede
   do cluster.

## Decisão
**Sidecar (c) com o contrato HTTP de (a).**

- Pod `ai/triage-webhook` com dois containers:
  - `webhook` (Go, `services/triage-webhook` no monorepo de agentes): recebe o
    Alertmanager em `:8080`, métricas em `:9090`.
  - `core` (Python, mesma imagem da frota de agentes, entrypoint
    `triage-serve`): `POST /triage` em `127.0.0.1:8081`, métricas em `:9091`.
- O núcleo **não tem Service nem CNP** — bind loopback; só a borda o alcança.
- Contrato síncrono: `POST /triage {"context"} → 200 {"report"}`. É localhost;
  job assíncrono com polling seria complexidade sem benefício.
- Se surgir um segundo consumidor do núcleo, a migração para (a) é mecânica:
  mudar o bind, criar Service e CNP. O contrato HTTP não muda.

### Deduplicação: in-memory, 1 réplica
Chave = `groupKey` + conjunto ordenado de `(fingerprint, startsAt)` dos alertas
firing. Janela TTL em memória (`DEDUP_TTL`, 6h). Com `replicas: 1` e strategy
`Recreate`, o mapa é o estado honesto: perder a janela num restart custa no
máximo uma triagem duplicada no reenvio do Alertmanager. **Regra registrada:
dedup migra para Valkey no dia em que `replicas > 1` — e não antes** (anti
fake-HA: Valkey não tornaria o serviço mais disponível, só adicionaria uma
dependência de rede e uma CNP).

### Coalescing é do Alertmanager, não da borda
Rota dedicada opt-in (`triage = "true"`) com `group_by: [namespace]`,
`group_wait: 2m`, `group_interval: 10m`, `repeat_interval: 12h`. A borda não
reimplementa janela de espera: alerta novo no grupo muda a chave de dedup e
gera re-triagem com contexto mais completo. **Invariante: `DEDUP_TTL` (6h) <
`repeat_interval` (12h)** — senão o reenvio periódico nunca re-tria incidente
longo. A rota usa `continue: true` e existe um catch-all explícito para o
Slack: sem ele, alerta triado deixaria de notificar humano (semântica de
routing do AM: child que casa suprime o receiver do pai).

### Backpressure e drenagem
- Fila limitada (`QUEUE_SIZE` 16); cheia → `429`. O Alertmanager é o retry —
  a borda não acumula buffer infinito nem persiste fila.
- `WORKERS` (2) é o teto de triagens concorrentes = teto de custo LLM.
- Shutdown (SIGTERM): borda para de aceitar → triagem **em curso termina**
  (context desacoplado do cancelamento, teto `TRIAGE_TIMEOUT` 10m) → fila
  restante é **descartada e contada** (`triage_webhook_jobs_dropped_on_shutdown_total`).
  Alerta ainda firing será reenviado; persistir a fila seria redundância.
- `terminationGracePeriodSeconds: 630 > TRIAGE_TIMEOUT`, e o núcleo usa
  `shutdown_timeout` de 600s no aiohttp — os três prazos são coerentes.

### Publicação
Fase B1: diagnóstico vai para o log estruturado da borda (VictoriaLogs).
Fase B2: `SlackPublisher` (thread no canal de alertas) e persistência — a
interface `publish.Publisher` é o ponto de extensão; o pipeline não muda.

O agente permanece read-only (ADR-0015): a triagem produz diagnóstico, nunca
mutação no cluster.

## Consequências
- Um único pod novo na rede; a CNP da triagem tem duas origens (vmalertmanager
  → 8080, vmagent → 9090/9091) e o litellm ganha o pod da triagem na whitelist
  da 4000.
- A borda Go é stdlib-only (métricas Prometheus in-tree, formato de exposição
  texto): binário estático mínimo e zero churn de deps. Se precisar de labels
  dinâmicos/exemplars, trocar por client_golang é mecânico e localizado.
- Versionamento atômico borda+núcleo no mesmo Deployment; em contrapartida,
  todo rollout reinicia ambos (aceitável: Recreate já é o contrato).
- Ativação é um passo separado e auditável: adicionar `triage: "true"` nos
  VMRules escolhidos. A infraestrutura sobe dark.
