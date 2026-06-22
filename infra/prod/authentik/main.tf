# Nome curto = canonico no bpg 0.109. A VM NÃO referencia o `.id` (computed ->
# forçaria replace); o file_id do disco é CONSTRUÍDO dos args conhecidos no plan.
resource "proxmox_download_file" "debian_cloud" {
  node_name           = var.proxmox_node
  datastore_id        = "local"
  content_type        = "iso" # bpg importa o qcow2 como disco; file_name precisa de .img
  file_name           = "debian-13-genericcloud-amd64.img"
  url                 = var.debian_cloud_image_url
  overwrite_unmanaged = true
}

resource "proxmox_virtual_environment_vm" "authentik" {
  name        = "authentik"
  node_name   = var.proxmox_node
  description = "Authentik IdP (SSO) tier-0 — VM autocontida (PG+redis no compose), fora do cluster"
  tags        = ["mgmt", "authentik", "sso"]

  cpu {
    cores = var.vcpus
    type  = "host"
  }

  memory {
    dedicated = var.memory
  }

  # Debian genericcloud NÃO traz qemu-guest-agent. Com enabled=true o provider
  # trava no Read esperando o agente (~15min). IP é estático, SSH conecta por IP.
  agent {
    enabled = false
  }

  # Disco único de boot (SO + PG + redis + media). file_id construído dos args
  # configurados do download (conhecidos no plan) -> gerir o download nunca
  # força replace da VM. depends_on garante a ordem em builds do zero.
  disk {
    datastore_id = var.datastore_id
    interface    = "virtio0"
    size         = var.boot_disk_size
    file_id      = "${proxmox_download_file.debian_cloud.datastore_id}:${proxmox_download_file.debian_cloud.content_type}/${proxmox_download_file.debian_cloud.file_name}"
    iothread     = true
    discard      = "on"
  }

  initialization {
    datastore_id = var.datastore_id
    ip_config {
      ipv4 {
        address = "${var.authentik_ip}/21"
        gateway = var.gateway_ip
      }
    }
    dns {
      servers = [var.gateway_ip] # resolve via UDR; nunca via si mesma
    }
    user_account {
      username = "root"
      keys     = [var.ssh_public_key]
    }
  }

  network_device {
    bridge = "vmbr0"
  }

  operating_system {
    type = "l26"
  }

  depends_on = [proxmox_download_file.debian_cloud]
}

# Provisionamento via SSH (1Password SSH agent). Re-provisiona quando o script
# muda (inclui o hash do compose, dos segredos e da config — via os ${...}).
resource "terraform_data" "authentik_provision" {
  depends_on = [proxmox_virtual_environment_vm.authentik]

  triggers_replace = [sha1(join("\n", local.authentik_script))]

  connection {
    type  = "ssh"
    host  = var.authentik_ip
    user  = "root"
    agent = true
  }

  provisioner "remote-exec" {
    inline = local.authentik_script
  }
}
