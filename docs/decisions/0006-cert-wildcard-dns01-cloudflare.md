---
tipo: adr
numero: 6
titulo: Certificado wildcard via ACME DNS-01 no Cloudflare, dois ClusterIssuers
status: aceito
fases: [3]
---

# ADR-0006 — Cert wildcard via DNS-01, staging + prod

## Status
Aceito (Fase 3).

## Contexto
Todos os serviços ficam sob `*.lab.the-lab.zone` e precisam de TLS válido sem expor HTTP-01
na borda.

## Decisão
Cert **wildcard** `*.lab.the-lab.zone` via ACME **DNS-01** no Cloudflare. **Dois**
ClusterIssuers (`letsencrypt-staging` + `letsencrypt-prod`), com account keys separadas. O
flip é declarativo (muda a annotation `issuerRef` → reemite sozinho, sem deletar secret).

## Porquê
Wildcard cobre todos os `*.lab` com um cert só; DNS-01 não exige expor HTTP-01. Staging
permanente valida serviços futuros sem gastar rate limit do prod; key por server é a prática
recomendada.

## Consequências
- A integração Gateway API do cert-manager precisa de `config.enableGatewayAPI: true`
  (desligada por default ≥1.15).
- Token Cloudflare via ESO no namespace `cert-manager` (cluster resource namespace).
