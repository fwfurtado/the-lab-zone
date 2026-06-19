output "harbor_url" {
  description = "URL do Harbor"
  value       = "https://${local.harbor_fqdn}"
}

output "harbor_ip" {
  value = var.harbor_ip
}

output "proxy_cache_projects" {
  description = "Projetos proxy cache que os mirrors do Talos apontam"
  value = {
    "docker.io" = "https://${local.harbor_fqdn}/v2/dockerhub-proxy"
    "ghcr.io"   = "https://${local.harbor_fqdn}/v2/ghcr-proxy"
    "quay.io"   = "https://${local.harbor_fqdn}/v2/quay-proxy"
  }
}
