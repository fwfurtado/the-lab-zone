---
tipo: adr
numero: 10
titulo: MCP servers via ToolHive operator (não servers soltos)
status: aceito
fases: [7]
relacionado: [runbooks/toolhive-mcp]
---

# ADR-0010 — ToolHive operator para MCP servers

## Status
Aceito (Fase 7).

## Contexto
Expor ferramentas MCP (`github`, `grafana`, `kubernetes`, `fastcrw`, `searxng`) pro
ecossistema agentic. A alternativa seria gerenciar cada MCP server solto (Deployment +
Service + RBAC à mão).

## Decisão
**ToolHive operator** com o CRD `MCPServer`, que padroniza secret/RBAC/proxy. Namespace mode
`allowedNamespaces: [ai, toolhive-system]`, instalado cluster-scoped (projeto `core`).
`github` e `fastcrw` rodam em **stdio + proxyMode streamable-http** (o modo http nativo deles
exige OAuth de cliente que o proxy não fornece; stdio também é imune ao MTU/drop do Cilium).

## Consequências
- O operator (v0.30.0) é imaturo: não propaga `sessionAffinity`, não recria Service
  deletado, reverte rollout restart — tratar o proxy como efêmero (delete pod) — ver runbook
  toolhive-mcp.
- Precisa de Kyverno pra contornar a incompatibilidade `sessionAffinity: ClientIP` com o
  Cilium (ADR-0011).
- `Ready` do ToolHive ≠ backend alcançável cross-pod.
