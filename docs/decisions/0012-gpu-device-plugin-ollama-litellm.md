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
Aceito (Fase 7).

## Contexto
RTX 3090 (24GB) no `worker-3-gpu` pra inferência local. A alternativa era o gpu-operator
inteiro.

## Decisão
- **GPU via device plugin standalone** (não o gpu-operator) — lab enxuto. RuntimeClass
  `nvidia` mapeando o runtime da system extension do Talos.
- **Ollama com `qwen3-coder:30b-a3b-q4_K_M`** (MoE 30B total / 3B ativos, q4 = 19GB) — cabe
  nos 24GB, mais rápido E mais capaz que um denso 14B. Contexto capado em 32768.
- **LiteLLM** como proxy. `qwen3-embedding` é alias **FIXO** (o LightRAG depende dele).
- **DCGM exporter** no `kube-system` (precisa de SYS_ADMIN+root; o Talos isenta o
  kube-system do PodSecurity).

## Consequências
- RuntimeClass `scheduling` não basta pra DaemonSet (nodeSelector/toleration explícitos no
  template) — ver runbook gpu.
- DCGM precisa de 1Gi e tag `-distroless`.
- O taint de GPU trava DaemonSets de telemetria já agendados (toleration específica).
