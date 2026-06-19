resource "proxmox_download_file" "debian_cloud" {
  node_name           = var.proxmox_node
  datastore_id        = "local"
  content_type        = "iso" # bpg importa o qcow2 como disco; file_name precisa de extensao .img
  file_name           = "debian-13-genericcloud-amd64.img"
  url                 = var.debian_cloud_image_url
  overwrite_unmanaged = true
}

resource "proxmox_virtual_environment_vm" "harbor" {
  name          = "harbor"
  node_name     = var.proxmox_node
  description   = "Harbor registry (proxy cache + imagens proprias + Trivy) - fora do cluster"
  tags          = ["mgmt", "harbor"]

  cpu {
    cores = var.vcpus
    type  = "host" # passa as flags reais da CPU
  }

  memory {
    dedicated = var.memory
  }

  agent {
    enabled = true # qemu-guest-agent (vem no cloud-init via script? Debian cloud ja inclui)
  }

  # Disco de boot — importa a imagem cloud
  disk {
    datastore_id = var.datastore_id
    interface    = "virtio0"
    size         = var.boot_disk_size
    file_id      = proxmox_download_file.debian_cloud.id
    iothread     = true
    discard      = "on"
  }

  # Disco DEDICADO pros blobs do Harbor (virtio1 -> /dev/vdb)
  disk {
    datastore_id = var.datastore_id
    interface    = "virtio1"
    size         = var.data_disk_size
    iothread     = true
    discard      = "on"
    backup       = false
  }

  initialization {
    datastore_id = var.datastore_id
    ip_config {
      ipv4 {
        address = "${var.harbor_ip}/21"
        gateway = var.gateway_ip
      }
    }
    dns {
      servers = [var.gateway_ip] # a VM resolve via UDR; nunca via si mesma
    }
    user_account {
      # Debian genericcloud: sshd com PermitRootLogin prohibit-password -> login
      # de root POR CHAVE funciona. Se sua imagem divergir, troque por um usuario
      # sudo e ajuste o connection.user do terraform_data.
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
}

# Provisionamento via SSH (1Password SSH agent). Re-provisiona quando o script muda.
resource "terraform_data" "harbor_provision" {
  depends_on = [proxmox_virtual_environment_vm.harbor]

  triggers_replace = [sha1(join("\n", local.harbor_script))]

  connection {
    type  = "ssh"
    host  = var.harbor_ip
    user  = "root"
    agent = true
  }

  provisioner "remote-exec" {
    inline = local.harbor_script
  }
}
