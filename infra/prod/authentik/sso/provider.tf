terraform {
  required_version = ">= 1.6"

  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "~> 2026.5" # casa com o server 2026.5.3 que o vm/ subiu
    }
  }
}

# url + token explícitos via var (vindas do op run --env-file=.env.tpl central).
# O provider também leria AUTHENTIK_URL/AUTHENTIK_TOKEN do env automaticamente,
# mas no teu padrão tudo passa por TF_VAR_* -> deixo explícito.
provider "authentik" {
  url   = var.authentik_url
  token = var.authentik_token
}
