output "forgejo_url" {
  value = "https://${local.forgejo_fqdn}"
}

output "forgejo_ip" {
  value = var.forgejo_ip
}

output "forgejo_clone_ssh" {
  description = "Prefixo de clone SSH (porta != 22 por causa do sshd da VM)"
  value       = "ssh://git@${local.forgejo_fqdn}:${var.forgejo_ssh_port}/"
}
