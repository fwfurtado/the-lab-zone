---
tipo: setup
fase: 7
titulo: Stack de IA — MCP, GPU e inferência local
relacionado: [decisions/0010-toolhive-operator-mcp, decisions/0011-kyverno-policy-engine, decisions/0012-gpu-device-plugin-ollama-litellm]
---

# Setup Fase 7 — Stack de IA

Sobe a camada de IA: MCP servers (ToolHive), Kyverno, GPU no `worker-3-gpu` (RTX 3090) com
Ollama + LiteLLM.

Ordem (nunca antes do CNI = wave 0): RuntimeClass `nvidia` (-1) → nvidia-device-plugin/kyverno
(1) → toolhive operator → MCP servers (ns ai) → ollama (5). O DCGM exporter que aparecia na
ordem histórica foi removido e não deve ser instalado.

## 7.1 Talos: habilitar a GPU
System extensions no schematic: `nvidia-container-toolkit-production` +
`nvidia-open-gpu-kernel-modules-production`. `nodeLabels` em `machine.nodeLabels`; taint via
`registerWithTaints` + `kubectl taint` imperativo (bridge). Smoke test com `nvidia-smi` num pod
`runtimeClassName: nvidia`.

## 7.2 Ollama
```bash
kubectl -n ai exec deploy/ollama -- ollama pull qwen3-coder:30b-a3b-q4_K_M
kubectl -n ai exec deploy/ollama -- ollama ps   # PROCESSOR=100% GPU, CONTEXT=32768
```
PVC `ollama-models` em `openebs-hostpath` (`Prune=false` blinda os modelos).

## 7.3 LiteLLM
Adicionar `qwen3-coder-30b-local` ao `model_list` (sem tocar no `qwen3-embedding`), `rollout
restart deploy/litellm`.

## 7.4 MCP servers
Cada `MCPServer` validado com `initialize` retornando `serverInfo` via proxy streamable-http.

## 7.5 DCGM exporter (removido)

O exporter previsto originalmente para observabilidade da GPU foi removido do setup. Não criar
ou sincronizar um `dcgm-exporter`, não reiniciar o vmagent por causa dele e não usar
`DCGM_FI_DEV_GPU_UTIL` como critério de saída. A observabilidade específica do DCGM não faz parte
do caminho ativo desta fase.

**Critério de saída:** 5 MCP servers respondem `initialize`; `ollama ps` 100% GPU; LiteLLM expõe
`qwen3-coder-30b-local` com inferência ponta a ponta.
