---
tipo: runbook
componente: sso-authentik
tags: [authentik, oidc, sso, langfuse, harbor, forgejo, grant-types, signing-key, issuer-trailing-slash]
fases: [9]
relacionado: [runbooks/gateway-dns]
---

# Authentik SSO: OIDC em 6 apps

SSO via Authentik em ArgoCD, Grafana, Open WebUI, Langfuse (in-cluster) + Harbor, Forgejo (VM
mgmt). Provider configurado via Terraform.

## `grant_types` vazio no Authentik 2026.5

**Sintoma:** todos os apps OIDC falhavam o fluxo com `invalid_request`.
**Causa:** o provider OAuth2 do Authentik 2026.5 não defaulta `grant_types`; sem ele não anuncia
`authorization_code`/`refresh_token`.
**Diagnóstico:** erro no início do fluxo, antes de qualquer redirect, em **todos** os apps de
uma vez → aponta pro IdP, não pro app.
**Fix:** `grant_types = ["authorization_code", "refresh_token"]` no `authentik_provider_oauth2`
(via `for_each`, corrigiu os 6 de uma vez).
**Lição:** erro idêntico em todos os apps = problema no provider compartilhado.

## `signing_key` ausente → HS256 vs RS256

**Sintoma:** "failed to verify the token" mesmo com login OK no Authentik.
**Causa:** sem `signing_key`, o Authentik assina o id_token em HS256; os clientes esperam RS256
validável via JWKS.
**Diagnóstico:** discovery expõe `id_token_signing_alg_values_supported: [RS256]`, mas o token
vinha HS256.
**Fix:** `signing_key = data.authentik_certificate_key_pair.default.id`.
**Lição:** OIDC com validação por JWKS exige chave assimétrica; conferir o `alg` do token vs
`*_signing_alg_values_supported` do discovery.

## Trailing slash no issuer — Langfuse vs Harbor (OPOSTOS)

**Sintoma:** Langfuse dava 301 no discovery; Harbor dava "failed to verify connection". Mesmo
IdP, sintomas diferentes.
**Causa:** o Authentik emite `issuer` **com** barra final. As libs reagem ao contrário:
- **Langfuse** (`openid-client`, Node): concatena a barra → `//.well-known` → 301. Precisa do
  endpoint **SEM** barra.
- **Harbor** (`go-oidc`, Go): faz `TrimSuffix` pro discovery (200 OK), mas valida o `issuer`
  **literal** → mismatch sem a barra. Precisa **COM** barra.
**Diagnóstico:** `curl` no `.well-known` de dentro do container + comparar o campo `issuer` do
JSON com o configurado.
**Lição:** o `issuer` do discovery é a autoridade; casar com o que **cada lib** espera. "Failed
to verify connection" no Harbor com curl OK = mismatch de issuer, não conectividade.

## Langfuse SSO não provisiona organização

**Sintoma:** login SSO OK, mas org e projetos somem (visão vazia).
**Causa:** SSO no Langfuse é **autenticação, não autorização**; `ALLOW_ACCOUNT_LINKING` só age na
criação; o login gerou identidade sem membership.
**Diagnóstico:** login local mostra org/projetos intactos → dados não sumiram, é a conta SSO sem
vínculo.
**Fix:** Org Settings → Members → Invite member com o email da conta SSO (Owner) → relogar.
**Lição:** diferente de Grafana/Open WebUI (que mapeiam role pelo claim `groups`), Langfuse exige
provisioning manual de org (Members) ou SCIM.

## Harbor exige `offline_access` no scope

**Sintoma:** login web OK, mas o CLI secret (`docker login`) não sobrevivia.
**Causa:** o Harbor usa refresh token pra manter o CLI secret; sem `offline_access`, não há
refresh.
**Fix:** scope mapping `offline_access` no provider Authentik + incluir no scope do Harbor.
**Lição:** `property_mappings` só **disponibiliza** o scope; o app só recebe refresh se **pedir**
`offline_access` — inócuo pros outros apps.

## Harbor — campos da UI trocados

Group Claim = `groups`; Group Filter = **vazio**; Username Claim = `preferred_username`. O "test
OIDC" valida só conexão/issuer, não os claims — campos de claim só quebram no login real.

## Harbor — migração OIDC só sem usuários locais

O Harbor só troca pra `oidc_auth` se não houver usuário local além do admin. Conferir antes;
usuário local (mesmo deletado) pode travar a migração.

## Harbor — DNS split-horizon + wildcard catch-all

"failed to verify connection" que era na verdade DNS (NXDOMAIN mascarado por wildcard catch-all)
— ver `runbooks/gateway-dns/`. Erro de TLS pode ser sintoma de DNS.

## Forgejo — auto-registration via SSO

**Sintoma:** primeiro login SSO recusado ("registration disabled").
**Causa:** `DISABLE_REGISTRATION=true` bloqueia o auto-register via OAuth, mesmo com
`ENABLE_AUTO_REGISTRATION=true`.
**Fix:** `DISABLE_REGISTRATION=false` + `ALLOW_ONLY_EXTERNAL_REGISTRATION=true` +
`oauth2_client.ENABLE_AUTO_REGISTRATION=true` (+ `USERNAME=preferred_username`,
`ACCOUNT_LINKING=auto`).
**Lição:** "registro só via SSO" = registro local fechado + externo liberado, não registro
globalmente desabilitado.

## Forgejo — callback = nome da auth source

O callback é `/user/oauth2/<Authentication Name>/callback`; o `<nome>` precisa bater com o
redirect no `data.tf`. O nome da source não é cosmético — define a URL de redirect.

## Recovery flow não bound ao brand

Recovery flow não vem vinculado ao brand por padrão. Usar `password` write-only do 1Password ao
criar usuários; akadmin reseta como break-glass (documentar separado dos apps).

## Não-decisões documentadas (com gatilho de retomada)

- **ArgoCD CLI gRPC-web atrás do Gateway — DESCARTADO.** O Cilium Gateway/Envoy converte
  gRPC-web→gRPC nativo (`grpcWebTranslation`), e o argocd-server insecure não fala gRPC nativo. Fix
  exigiria GatewayClass dedicada — over-engineering pra lab. CLI fica no `argocd login --core`;
  UI+RBAC via SSO funcionam. Admin local de DR.
- **Hubble forward-auth — ADIADO p/ Cilium 1.20.** O Gateway API do Cilium não tem external auth
  no 1.19.4; `HTTPRouteExternalAuth` (GEP-1494) só chega no 1.20. Hubble UI segue por
  port-forward. Retomar: GEP-1494 GA + outpost in-cluster + filtro ext_auth no HTTPRoute +
  `signing_key` no `authentik_provider_proxy.hubble`.

## Lição transversal

Erro idêntico em todos os apps = provider compartilhado. Cada lib OIDC trata issuer/claims
diferente (trailing slash oposto entre Langfuse e Harbor). SSO ≠ provisioning de autorização
(Langfuse). Registrar não-decisões com gatilho de retomada vale tanto quanto registrar fixes.
