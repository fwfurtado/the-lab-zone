output "url" {
  value = "https://auth.mgmt.the-lab.zone"
}

output "ip" {
  value = var.authentik_ip
}

output "handoff" {
  description = "O token de API do admin (bootstrap) NÃO é exposto aqui — ele é o valor de var.authentik_admin_token, guardado no 1Password, e é o que o prompt 2 (SSO) consome."
  value       = "API admin token: 1Password (op://homelab/Authentik/admin-api-token)"
}
