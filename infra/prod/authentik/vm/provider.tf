terraform {
  required_version = "1.15.8"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.109.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true

  # SSH ao HOST pve — obrigatório porque a VM importa o cloud image como disco
  # (qm importdisk é CLI, não tem API). Reaproveita o 1Password SSH agent.
  # A pública precisa estar em /root/.ssh/authorized_keys do pve.
  ssh {
    agent    = true
    username = "root"
  }
}
