terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.109.0"
    }
    powerdns = {
      source  = "pan-net/powerdns"
      version = "1.5.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true
}

provider "powerdns" {
  # SEMPRE por IP — nunca por nome da própria zona (anti-circularidade)
  server_url = "http://${var.dns_ip}:8081"
  api_key    = var.pdns_api_key
}
