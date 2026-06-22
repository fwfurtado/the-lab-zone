# ── Flows e mappings built-in ───────────────────────────────────────────────
data "authentik_flow" "authorization" {
  slug = var.authorization_flow_slug
}

data "authentik_flow" "invalidation" {
  slug = var.invalidation_flow_slug
}

# Scope mappings padrão (openid/email/profile). [CONFERIR] os nomes na tua
# instância com: terraform console -> data.authentik_property_mapping_provider_scope...
# ou pela UI (Customization > Property Mappings).
data "authentik_property_mapping_provider_scope" "openid" {
  name = "authentik default OAuth Mapping: OpenID 'openid'"
}
data "authentik_property_mapping_provider_scope" "email" {
  name = "authentik default OAuth Mapping: OpenID 'email'"
}
data "authentik_property_mapping_provider_scope" "profile" {
  name = "authentik default OAuth Mapping: OpenID 'profile'"
}

# --- Certificado e chave para OAuth2 (self-signed) ---
data "authentik_certificate_key_pair" "default" {
  name = "authentik Self-signed Certificate"
}

# ── Scope mapping de GROUPS (não é built-in) ────────────────────────────────
# Emite o claim `groups` com os grupos do usuário. Necessário pro RBAC por
# grupo no ArgoCD/Grafana/Harbor/Forgejo.
resource "authentik_property_mapping_provider_scope" "groups" {
  name       = "the-lab-zone groups"
  scope_name = "groups"
  expression = "return [group.name for group in request.user.ak_groups.all()]"
}

locals {
  apps_domain = "${var.apps_subdomain}.${var.base_domain}" # lab.the-lab.zone
  mgmt_domain = "${var.mgmt_subdomain}.${var.base_domain}" # mgmt.the-lab.zone

  common_scopes = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    authentik_property_mapping_provider_scope.groups.id,
  ]

  # ─────────────────────────────────────────────────────────────────────────
  # Um registro por app OIDC. O `secret` referencia a var (op run injeta).
  # [CONFERIR] cada `redirects` contra a doc do app e os hostnames (lab vs mgmt).
  # Declarar TODOS de uma vez aqui é SEGURO — só cria objetos no Authentik, não
  # afeta os apps até cada um ser configurado no lado-cluster. O rollout app-a-app
  # (com validação de login) acontece lá, começando pelo ArgoCD.
  # ─────────────────────────────────────────────────────────────────────────
  oidc_apps = {
    argocd = {
      display = "Argo CD"
      slug    = "argocd"
      secret  = var.oidc_secret_argocd
      icon    = "https://argo-cd.readthedocs.io/en/stable/assets/logo.png"
      launch  = "https://argocd.${local.apps_domain}"
      redirects = [
        "https://argocd.${local.apps_domain}/auth/callback", # UI
        "http://localhost:8085/auth/callback",               # CLI (argocd login --sso)
      ]
    }
    grafana = {
      display   = "Grafana"
      slug      = "grafana"
      secret    = var.oidc_secret_grafana
      icon      = "https://grafana.com/static/img/menu/grafana2.svg"
      launch    = "https://grafana.${local.apps_domain}"
      redirects = ["https://grafana.${local.apps_domain}/login/generic_oauth"]
    }
    open-webui = {
      display   = "Open WebUI"
      slug      = "open-webui"
      secret    = var.oidc_secret_open_webui
      icon      = "https://openwebui.com/favicon.png"
      launch    = "https://chat.${local.apps_domain}" # [CONFERIR] subdomínio real
      redirects = ["https://chat.${local.apps_domain}/oauth/oidc/callback"]
    }
    langfuse = {
      display = "Langfuse"
      slug    = "langfuse"
      secret  = var.oidc_secret_langfuse
      icon    = "https://langfuse.com/icon.png"
      launch  = "https://langfuse.${local.apps_domain}"
      # Langfuse: /api/auth/callback/<id do provider custom>. id = "authentik".
      redirects = ["https://langfuse.${local.apps_domain}/api/auth/callback/authentik"]
    }
    harbor = {
      display   = "Harbor"
      slug      = "harbor"
      secret    = var.oidc_secret_harbor
      icon      = "https://goharbor.io/img/logos/harbor-icon-color.png"
      launch    = "https://harbor.${local.mgmt_domain}"
      redirects = ["https://harbor.${local.mgmt_domain}/c/oidc/callback"]
    }
    forgejo = {
      display = "Forgejo"
      slug    = "forgejo"
      secret  = var.oidc_secret_forgejo
      icon    = "https://forgejo.org/_astro/logo.svg"
      # Forgejo: /user/oauth2/<nome da source>/callback. source = "authentik".
      launch    = "https://git.${local.mgmt_domain}"
      redirects = ["https://git.${local.mgmt_domain}/user/oauth2/authentik/callback"]
    }
  }
}
