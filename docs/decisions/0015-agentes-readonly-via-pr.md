---
tipo: adr
numero: 15
titulo: Agentes de IA são read-only e só propõem mudanças via PR
status: aceito
fases: [11]
relacionado: [runbooks/toolhive-mcp]
---

# ADR-0015 — Governança dos agentes: read-only, mudanças só via PR

## Status
Aceito (Fase 11 / camada de agentes — invariante de governança).

## Contexto
A camada de agentes (MCP servers + Goose) opera sobre o cluster de produção do homelab. Dar a
um agente capacidade de mutar o cluster diretamente é risco inaceitável num ambiente que é a
fonte da verdade via GitOps.

## Decisão
Os MCP servers expostos aos agentes são **read-only** (VictoriaMetrics, Qdrant, ArgoCD com
tools read-only). Agentes podem **propor** mudanças apenas via **Pull Request** no repo
GitOps — **nunca** mutam o cluster diretamente. O ArgoCD continua sendo o único caminho de
mudança (commit → sync).

## Consequências
- O blast radius de um agente comprometido/alucinado é limitado a abrir um PR (revisável),
  não a aplicar mudança no cluster.
- Coerente com ADR-0001 (GitOps puro): a mutação sempre passa pelo Git, inclusive a originada
  por agente.
- MCP servers de escrita, se um dia existirem, precisam de uma decisão separada que reavalie
  este invariante.
