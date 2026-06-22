# Hubble UI não tem auth nativa -> Proxy Provider (forward-auth), não OIDC.
#
# ESTE arquivo declara só o LADO-IdP: o proxy provider, a application e o
# outpost. O LADO-CLUSTER (Deployment do outpost dentro do cluster + a ligação
# de forward-auth no Cilium Gateway, via ExtAuthz/HTTPRoute filter) vem depois,
# e o Hubble é o ÚLTIMO app a validar (o mais chato de fechar).

resource "authentik_provider_proxy" "hubble" {
  name               = "Hubble UI"
  external_host      = "https://hubble.${local.apps_domain}" # [CONFERIR] subdomínio real
  mode               = "forward_single"
  authorization_flow = data.authentik_flow.authorization.id
  invalidation_flow  = data.authentik_flow.invalidation.id
}

resource "authentik_application" "hubble" {
  name              = "Hubble UI"
  slug              = "hubble"
  protocol_provider = authentik_provider_proxy.hubble.id
  meta_icon         = "https://raw.githubusercontent.com/cilium/cilium/main/Documentation/images/logo-solo.svg"
  meta_launch_url   = "https://hubble.${local.apps_domain}"
  group             = "the-lab-zone"
}

# Outpost dedicado pro proxy do Hubble. O Deployment real roda IN-CLUSTER
# (lado-cluster); aqui só registramos o outpost e anexamos o provider.
# Alternativa: usar o embedded outpost do Authentik — mas um outpost in-cluster
# fica na mesma rede do Gateway e evita expor o forward-auth pra fora.
resource "authentik_outpost" "hubble" {
  name = "the-lab-zone proxy outpost"
  type = "proxy"
  protocol_providers = [
    authentik_provider_proxy.hubble.id,
  ]
  # service_connection e config (authentik_host etc.) ficam pro lado-cluster,
  # onde o Deployment do outpost sabe como falar com o Authentik.
}
