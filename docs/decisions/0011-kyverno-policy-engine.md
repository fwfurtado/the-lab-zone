---
tipo: adr
numero: 11
titulo: Kyverno como policy engine (mutate do sessionAffinity do ToolHive)
status: aceito
fases: [7]
relacionado: [runbooks/toolhive-mcp]
---

# ADR-0011 — Kyverno como policy engine

## Status
Aceito (Fase 7).

## Contexto
O ToolHive cria Services de backend com `sessionAffinity: ClientIP`, que quebra com o
KubeProxyReplacement do Cilium. A alternativa era um patch manual recorrente a cada Service
efêmero.

## Decisão
**Kyverno** como policy engine; primeiro uso: ClusterPolicy que faz mutate
`spec.sessionAffinity: None` em Service no ns `ai` com label `toolhive: "true"`. Mutate
idempotente com guards anti-loop (precondition exclui o Service do proxy que o operator
gerencia).

## Consequências
- Mutate de admissão em recurso criado por controller-em-runtime é seguro porque (a) o
  recurso não está sob reconciliação apertada e (b) a policy é idempotente e exclui o que o
  controller-pai gerencia.
- A instalação do Kyverno tem quirks de drift/CRDs grandes (`ServerSideApply`,
  `ignoreDifferences` com group sem `/v1`) — ver runbook toolhive-mcp.
