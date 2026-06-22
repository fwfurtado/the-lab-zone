# Um OAuth2 provider + uma Application por app, via for_each sobre o map.
# client_id = chave do app (estável, legível, não é segredo).
# client_secret = setado explícito (input) -> evita o bug #5121 (secret gerado
# pelo Authentik vindo com caracteres ilegais no output do TF).

resource "authentik_provider_oauth2" "this" {
  for_each = local.oidc_apps

  name               = each.value.display
  client_id          = each.key
  client_secret      = each.value.secret
  client_type        = "confidential"
  authorization_flow = data.authentik_flow.authorization.id
  invalidation_flow  = data.authentik_flow.invalidation.id
  property_mappings  = local.common_scopes
  grant_types        = ["authorization_code", "refresh_token"]

  signing_key = data.authentik_certificate_key_pair.default.id

  # allowed_redirect_uris é nested attribute (lista de objetos), atribuído com `=`.
  allowed_redirect_uris = [
    for uri in each.value.redirects : {
      matching_mode = "strict"
      url           = uri
    }
  ]
}

resource "authentik_application" "this" {
  for_each = local.oidc_apps

  name              = each.value.display
  slug              = each.value.slug
  protocol_provider = authentik_provider_oauth2.this[each.key].id
  meta_icon         = each.value.icon
  meta_launch_url   = each.value.launch
  group             = "the-lab-zone" # agrupa os apps no dashboard do Authentik
}
