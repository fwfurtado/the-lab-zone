---
tipo: adr
numero: 2
titulo: Admin local do ArgoCD permanece habilitado para sempre
status: aceito
fases: [2, 9]
---

# ADR-0002 — Admin local do ArgoCD sempre habilitado

## Status
Aceito (Fase 2), reafirmado na Fase 9 (SSO).

## Contexto
Com SSO (Authentik) na Fase 9, seria tentador desabilitar o admin local do ArgoCD por
higiene de segurança.

## Decisão
O admin local do ArgoCD permanece habilitado **para sempre**. Quando o SSO existe, ele é
conveniência; o admin local é a **porta de emergência do DR**.

## Consequências
- Num desastre onde o Authentik (ou o Gateway, ou o DNS) está fora, ainda há acesso ao
  ArgoCD via `argocd login --core` + admin local.
- A decisão de não corrigir o ArgoCD CLI gRPC-web atrás do Gateway (ver runbook
  sso-authentik) se apoia nesta: a UI+RBAC via SSO funcionam, e o break-glass é o admin local.
