---
tipo: adr
numero: 16
titulo: Headroom descartado para a triagem; proteção de contexto via cap próprio
status: aceito
fases: [11]
relacionado: [decisions/0015-agentes-readonly-via-pr, decisions/0012-gpu-device-plugin-ollama-litellm]
---

# ADR-0016 — Headroom descartado para a triagem; proteção de contexto via cap próprio

## Status
Aceito (Fase 11 / camada de agentes). Rejeita a adoção do Headroom no caminho da triagem.

## Contexto
O agente de triagem (ADR-0015) chegou a estourar o context window ao despejar um tool result
gigante (Summary API do kubelet, log volumoso). Avaliamos o **Headroom** (compressão de
contexto para LLMs) como camada de mitigação, integrado ao LiteLLM.

Testamos três formas de integração:

1. **Callback in-process no LiteLLM** (`litellm_settings.callbacks`): não engancha. O
   `HeadroomCallback` herda só de `object` e imita a interface `CustomLogger` por duck-typing;
   o proxy só registra o `async_pre_call_hook` de callbacks que são de fato `CustomLogger`,
   então o callback carrega mas nunca roda (`callback-duration-ms: 0.0`).
2. **Guardrail nativo** (`guardrails: [{guardrail: headroom, mode: pre_call}]`): é o caminho
   suportado, mas exige **LiteLLM ≥ 1.92.x** — estamos na 1.90.2 (chart 1.89.1). Bumpar o
   gateway inteiro (QA, LightRAG, Open WebUI) por essa feature é risco desproporcional.
3. **Proxy standalone** (Opção A): o agente aponta pro `headroom proxy`, que comprime e
   encaminha ao LiteLLM. Subiu e funcionou end-to-end — e foi o que permitiu medir.

Medição do run real da triagem através do proxy Headroom (5 requests, 99.544 tokens de input):
**requests_compressed: 0, tokens saved: 0, avg_compression_pct: 0.0**, latência média
**14,8s** e máxima **51,5s** por request. O diagnóstico saiu correto (o modelo leu os números
certos e achou os CrashLoops reais), apenas mais lento.

A causa do 0% é **arquitetural, não de configuração nem de versão**. O SmartCrusher do Headroom
comprime **arrays JSON homogêneos** em tool outputs (listas de dicts/strings/números, logs de
build) — é daí que vêm os 83–95% de economia da ferramenta. A triagem produz **estado k8s
heterogêneo** (YAML de eventos, tabela de pods estilo `kubectl`, Summary API) e **já enxuto na
origem**: o system prompt força `hits`/`facets`/`stats_query` antes de linhas cruas, e o único
output grande já chega **truncado pelo nosso cap** antes de qualquer compressão. Não há config
(`compress_user_messages`, `min_tokens_to_crush`, `target_ratio`) que crie compressibilidade
num formato que o SmartCrusher não parseia.

## Decisão
- **Headroom NÃO entra no caminho da triagem** (nem proxy, nem guardrail, nem MCP). O app é
  removido do repo (`apps/ai/headroom`) e a triagem aponta direto pro LiteLLM.
- **A proteção de contexto é feita por cap próprio no runtime do agente**, determinístico e
  fora de qualquer serviço externo:
  - `MAX_TOOL_RESULT_CHARS` (60000): trunca o tool result **antes** de entrar no contexto,
    com nota de truncamento que instrui o modelo a refinar a chamada (janela de tempo, stream
    selector, namespace).
  - `UsageLimits` (request/tool-calls/total-tokens): teto rígido por execução, evita loops e
    despejos gigantes.
- O LiteLLM permanece **stock** (`ghcr.io/berriai/litellm-database`, sem imagem custom, sem
  shim de callback).

## Consequências
- Zero latência extra no hot path da triagem — relevante porque o agente dispara em resposta a
  alerta, onde o MTTR importa. O cap resolve o mesmo problema que o Stage 3 (context fitting)
  do Headroom resolveria, de forma determinística e a 0ms.
- Menos superfície e menos acoplamento: sem imagem custom do LiteLLM, sem callback in-process
  acoplado à interface interna do proxy (que muda entre versões), sem um serviço a mais no
  caminho de request.
- **Gatilho de reabertura**: o Headroom volta à mesa apenas se surgir um agente cujos tool
  outputs sejam **arrays JSON homogêneos, grandes e não-truncáveis** (ex.: agente sobre dumps
  de banco / API paginada, ou um agente de coding com `headroom-ai[code]` sobre outputs de
  repo). Nesses casos o SmartCrusher rende e o CCR (`retrieve`) preserva o item cru. Não é o
  caso da triagem, que lê estado heterogêneo e truncável.
- Aprendizado registrado para futuras integrações de terceiros no gateway: validar o **contrato
  de integração suportado pela versão fixada** (não pela doc mais recente) **antes** de escolher
  a abordagem, e — para imagens de terceiros — inspecionar `Entrypoint`/`Cmd`/`User` e as tags
  publicadas (`docker inspect`, `crane ls`) antes de escrever o manifesto.
