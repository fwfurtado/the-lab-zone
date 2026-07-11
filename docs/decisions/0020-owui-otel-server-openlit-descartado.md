---
tipo: adr
numero: 20
titulo: OWUI — OTel do server HTTP; OpenLIT descartado
status: aceito
fases: [7]
relacionado: [decisions/0012-gpu-device-plugin-ollama-litellm, decisions/0018-lightrag-desligado-rag-fora-de-escopo]
---

# ADR-0020 — Observabilidade do open-webui: OTel do server sim, OpenLIT não

## Status
Aceito. Ativa a instrumentação OTel nativa do server do open-webui; descarta o
OpenLIT como forma de obter trace GenAI do OWUI.

## Contexto
Duas frentes foram avaliadas para o open-webui:

1. **GenAI-aware (custo/token/latência de LLM)** — via OpenLIT.
2. **Saúde da app web (rota/DB/HTTP)** — via OTel nativo do server do OWUI.

São eixos ortogonais: OpenLIT instrumenta a camada LLM; o OTel do server
instrumenta o processo web (FastAPI/SQLAlchemy/Redis/httpx). Um não substitui o
outro.

## Decisão 1 — OpenLIT descartado (frente 1)
O modelo canônico do OpenLIT no OWUI é um **Pipe** no Pipelines server: o pipe
cria o próprio client OpenAI e faz a chamada, e o OpenLIT auto-instrumenta *esse*
client. Isso exige **rotear a inferência pelo Pipelines** — que no nosso setup
NÃO acontece: `openaiBaseApiUrl` aponta direto pro LiteLLM, e o filtro Langfuse
atual é um Filter (inlet/outlet) que só observa. Adotar OpenLIT no modelo
canônico significaria rearquitetar o caminho de inferência para passar por um
Pipelines **legacy** (deprecado pelo upstream em favor de Functions in-process),
adicionando um hop no caminho crítico.

E o ganho seria marginal, porque o **LiteLLM já cobre a camada LLM melhor** para
o nosso caso:

| Sinal | LiteLLM (hoje) | OpenLIT |
|---|---|---|
| Modelo + cadeia de fallback | Sim (vê o que o router fez) | Não (cego a fallback) |
| Tokens | Sim | Sim |
| Custo | EFETIVO (`x-litellm-response-cost`) | Estimado por tabela (errado p/ nossos providers) |
| Atribuição de usuário | Sim (`X-OpenWebUI-User-Id`) | Não |
| GPU | Já temos DCGM (Fase 7) | Redundante |
| Prompt/response | Desligado por design (anti-duplicação) | Capturaria (indesejado aqui) |

**Gatilho de reavaliação:** se o LiteLLM sair do caminho (inferência direta
OWUI→provider, sem gateway), ninguém emite o span GenAI — aí o OpenLIT volta à
mesa. Enquanto o LiteLLM for o gateway, ele é a fonte autoritativa.

**Pendência não resolvida por nenhuma das opções:** o span do LiteLLM e o trace
do OWUI são desconexos (sem propagação de `traceparent` OWUI→LiteLLM). Costurar
é propagação de contexto nas apps — fora do escopo desta ADR.

## Decisão 2 — OTel do server ativado (frente 2)
Instrumentação nativa do OWUI ligada por env var (sem rebuild):
`ENABLE_OTEL` + `ENABLE_OTEL_TRACES` + `ENABLE_OTEL_METRICS`. O toggle de traces
é separado do master flag desde 0.6.26 (upstream #17041) — só `ENABLE_OTEL` não
exporta traces.

- Exporter **gRPC :4317** no collector node-local (`http://$(HOST_IP):4317`),
  `HOST_IP` de `status.hostIP`. O receiver grpc do collector escuta em
  `MY_POD_IP:4317`, publicado via hostPort (default do chart em daemonset).
- `service.name=open-webui`. Vai **só pro Tempo** (fanout tudo→Tempo). NÃO entra
  no filtro `langfuse_agents_only`: telemetria de infra não pertence ao Langfuse.
- Egress no ns `ai` é liberado (CNPs são ingress-only) — nenhuma CNP nova.

## Consequências
- Ganhamos RED da app web do OWUI (latência de rota, erro HTTP, query de banco)
  no Tempo/VM — o que o span do LiteLLM não cobre.
- O caminho de inferência **não muda**: OWUI→LiteLLM direto, Pipelines segue só
  como observador lateral (filtro Langfuse).
- Ressalva de protocolo (upstream #16183): span exporter em http faz métricas
  irem por gRPC; evitado ao fixar tudo em gRPC :4317.
