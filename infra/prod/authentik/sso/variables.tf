# ── Conexão com o Authentik (handoff do vm/) ────────────────────────────────
variable "authentik_url" {
  type        = string
  default     = "https://auth.mgmt.the-lab.zone"
  description = "URL do Authentik (a VM do submódulo vm/)."
}

variable "authentik_token" {
  type        = string
  sensitive   = true
  description = "Token de API do akadmin. Handoff do vm/: op://homelab/Authentik/admin-api-token."
}

# ── Domínios (mesma convenção do resto do repo) ─────────────────────────────
variable "base_domain" {
  type    = string
  default = "the-lab.zone"
}

variable "apps_subdomain" {
  type        = string
  default     = "lab"
  description = "Apps in-cluster pelo Gateway: <app>.lab.the-lab.zone."
}

variable "mgmt_subdomain" {
  type        = string
  default     = "mgmt"
  description = "VMs de management: <vm>.mgmt.the-lab.zone."
}

# ── Flows (slugs built-in; ajuste se renomeou na instalação) ────────────────
variable "authorization_flow_slug" {
  type        = string
  default     = "default-provider-authorization-explicit-consent"
  description = "Consent explícito na 1a vez por app. Troque pelo -implicit-consent p/ UX sem tela de consent."
}

variable "invalidation_flow_slug" {
  type        = string
  default     = "default-provider-invalidation-flow"
  description = "Flow de invalidação do provider (logout). [CONFERIR] o slug na tua instância se o plan reclamar."
}

# ───────────────────────────────────────────────────────────────────────────
# client_secret por app — UMA var por app (sensível).
#
# FLUXO "1Password = fonte única, dois consumidores":
#   1. `just gen-secret <app>` gera o secret e grava no item oidc-<app>
#      do vault the-lab-zone (client_id + client_secret).
#   2. AQUI (TF, op run): lido como TF_VAR_oidc_secret_<app> -> seta no Authentik.
#   3. O MESMO item é lido pelo ESO no cluster (ExternalSecret por app) e vira
#      o Secret que o values do app consome.
#
# Uma var por app (em vez de um map em JSON) porque o `op run` interpola op://
# de forma confiável em vars escalares, não dentro de um JSON inline.
# ───────────────────────────────────────────────────────────────────────────
variable "oidc_secret_argocd" {
  type      = string
  sensitive = true
}
variable "oidc_secret_grafana" {
  type      = string
  sensitive = true
}
variable "oidc_secret_open_webui" {
  type      = string
  sensitive = true
}
variable "oidc_secret_langfuse" {
  type      = string
  sensitive = true
}
variable "oidc_secret_harbor" {
  type      = string
  sensitive = true
}
variable "oidc_secret_forgejo" {
  type      = string
  sensitive = true
}
