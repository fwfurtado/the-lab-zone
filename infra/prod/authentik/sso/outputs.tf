# Issuer por app (OIDC discovery: <issuer>/.well-known/openid-configuration).
# É o que cada app precisa no values do lado-cluster. SEM secrets — esses vêm
# do 1Password via ESO.
#
# No Authentik o issuer (per-provider) é:
#   https://auth.mgmt.the-lab.zone/application/o/<application-slug>/
output "issuers" {
  description = "issuer OIDC por app (colar no values do lado-cluster)."
  value = {
    for k, app in local.oidc_apps :
    k => "${var.authentik_url}/application/o/${app.slug}/"
  }
}

# Endpoints comuns (iguais pra todos; o issuer acima já basta pra discovery).
output "well_known_base" {
  value = "${var.authentik_url}/application/o/<slug>/.well-known/openid-configuration"
}

output "hubble_external_host" {
  value = authentik_provider_proxy.hubble.external_host
}
