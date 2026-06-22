# infra/prod/authentik/sso/directory.tf
#
# Grupos e usuários do dia-a-dia.
#
# MODELO DE PERMISSÃO DO AUTHENTIK: "superuser" é propriedade do GRUPO
# (is_superuser), não do usuário. "Não-admin" = não pertencer a nenhum grupo
# com is_superuser=true. O akadmin (break-glass) vive no grupo built-in
# "authentik Admins" — NÃO mexemos nele aqui; ele continua sendo a porta de DR.
#
# the-lab-admins NÃO é superuser do Authentik (não administra o IdP). É só o
# grupo que o claim `groups` emite e que o RBAC dos apps mapeia pra role admin
# (ex.: policy.csv do ArgoCD -> `g, the-lab-admins, role:admin`).

resource "authentik_group" "the_lab_admins" {
  name         = "the-lab-admins"
  is_superuser = false # administra os APPS via RBAC, não o Authentik
}

resource "authentik_user" "fwfurtado" {
  username = "fwfurtado"
  name     = "Fernando Furtado"
  email    = "fwfurtado@the-lab.zone"
  groups   = [authentik_group.the_lab_admins.id]
}
