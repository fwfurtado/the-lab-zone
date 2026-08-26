---
tipo: adr
numero: 12
titulo: GPU via device plugin standalone, Ollama (qwen3-coder MoE) + LiteLLM
status: aceito
fases: [7]
relacionado: [runbooks/gpu]
---

# ADR-0012 — Inferência local: device plugin + Ollama + LiteLLM

## Status
Aceito (Fase 7) para o device plugin standalone, Ollama e LiteLLM. O DCGM exporter foi
removido do setup ativo; a referência abaixo é somente o registro da decisão histórica. Não
instalar nem reintroduzir DCGM como parte deste setup.
Nota (ADR-0018): o alias `qwen3-embedding` era "FIXO por causa do LightRAG"; o LightRAG foi
desligado, mas o alias permanece por seguir em uso.

## Contexto
RTX 3090 (24GB) no `worker-3-gpu` pra inferência local. A alternativa era o gpu-operator
inteiro.

## Decisão
- **GPU via device plugin standalone** (não o gpu-operator) — lab enxuto. RuntimeClass
  `nvidia` mapeando o runtime da system extension do Talos.
- **Ollama com `qwen3-coder:30b-a3b-q4_K_M`** (MoE 30B total / 3B ativos, q4 = 19GB) — cabe
  nos 24GB, mais rápido E mais capaz que um denso 14B. Contexto capado em 32768.
- **LiteLLM** como proxy. `qwen3-embedding` é alias **FIXO** (o LightRAG depende dele).
- **DCGM exporter** — decisão histórica: previa um exporter no `kube-system` (com
  `SYS_ADMIN`+root; o Talos isenta o `kube-system` do PodSecurity). Foi removido do setup
  ativo e não deve ser instalado.

## Consequências
- A experiência histórica com um DaemonSet mostrou que RuntimeClass `scheduling` não basta:
  `nodeSelector`/toleration precisam estar explícitos no template — ver o runbook arquivado.
- **Histórico do DCGM removido:** o exporter exigia 1Gi e tag `-distroless`; esses requisitos não
  são instruções para o setup atual.
- O taint de GPU trava DaemonSets de telemetria já agendados (toleration específica).
