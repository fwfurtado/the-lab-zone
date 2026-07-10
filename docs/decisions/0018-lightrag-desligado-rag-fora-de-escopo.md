---
tipo: adr
numero: 18
titulo: LightRAG desligado; pipeline RAG fora de escopo
status: aceito
fases: [7]
relacionado: [decisions/0009-data-platform-stores, decisions/0012-gpu-device-plugin-ollama-litellm]
supersede-parcial: [decisions/0009-data-platform-stores, decisions/0012-gpu-device-plugin-ollama-litellm]
---

# ADR-0018 — LightRAG desligado; pipeline RAG fora de escopo

## Status
Aceito. Reverte a parte "RAG/LightRAG" das decisões 0009 (stores) e 0012
(alias de embedding), sem removê-las: os stores permanecem, só deixam de ter
o LightRAG como consumidor.

## Contexto
O LightRAG (Fase 7) nunca entrou em uso efetivo. A observabilidade dele vivia
num silo: a imagem `lightrag-langfuse` usa o wrapper nativo `langfuse.openai`,
que exporta trace **direto** para o projeto Langfuse `rag` via SDK — não passa
pelo OTel Collector, logo não gera `span_metrics`/`service_graph` nem entra no
Tempo. Instrumentá-lo "de primeira classe" exigiria trocar o caminho nativo por
OTLP (OpenLIT → collector) e rebuildar a imagem.

Avaliado o custo/benefício, a decisão foi **desligar** em vez de instrumentar:
sem uso real, não há custo de RAG a analisar nem cadeia OWUI→LightRAG→LiteLLM a
atribuir. Instrumentar seria trabalho a favor de um serviço morto.

## Decisão
Remover o LightRAG por completo e o que só existia para servi-lo:

- **App**: `apps/ai/lightrag/` inteiro (deployment/service/route/pvc/ESO). O
  ApplicationSet `ai` (recurse + prune) poda o child Application; o PVC
  `lightrag-data` é podado junto (OpenEBS LocalPV, reclaim=Delete → dados
  apagados).
- **CNPG**: role `lightrag` e Database/secret `cnpg-role-lightrag`.
- **LiteLLM**: `model_name: lightrag` e o mapeamento `LIGHTRAG_API_KEY` no ESO.
  O alias `qwen3-embedding` **permanece** (segue em uso fora do LightRAG).
- **CNPs**: `lightrag` removido das allow-lists de litellm, postgresql, qdrant
  e langfuse. No **memgraph**, LightRAG era o único cliente → a CNP vira
  default-deny puro (`ingress: - {}`). Na **langfuse**, a origem fantasma
  `pipelines` (gancho pré-planejado para instrumentar o open-webui) também sai,
  já que a instrumentação do OWUI saiu de escopo; `opentelemetry-collector`
  permanece (ingestão OTLP dos agentes).
- **Analytics**: `mart_rag_interactions` (dbt) deletado — dependia do projeto
  `rag` e de custo efetivo do LightRAG. Validado com `dbt parse`.

O projeto Langfuse `rag` é deletado pela UI (fora do GitOps).

## Consequências
- **Qdrant e Memgraph ficam sem consumidor.** Qdrant ainda serve o `qdrant-mcp`
  e a memória de triagem (qa-indexer/triage-indexer), então permanece. O
  **Memgraph fica ocioso** — não é removido aqui (fora de escopo), mas é
  candidato a desligamento futuro; hoje só custa recursos.
- Fila de trabalho colapsa: os itens "instrumentar terceiros no Langfuse",
  "RAG cost analytics (dbt)" e "atribuição de custo por interação" perdem o
  objeto e são encerrados.
- Reversão não é barata: reinstrumentar exigiria recriar app, role, Database,
  aliases e reingerir o corpus (o PVC foi apagado). Aceitável — a decisão é
  deliberada, não uma pausa.
