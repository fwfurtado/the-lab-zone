# Nome curto = canonico no bpg 0.109 (o longo eh deprecated). Este recurso NAO
# suporta `terraform import`, entao a VM NAO referencia o `.id` dele (que seria
# "known after apply" e forcaria replace). Veja o file_id do disco abaixo.
resource "proxmox_download_file" "debian_cloud" {
  node_name           = var.proxmox_node
  datastore_id        = "local"
  content_type        = "iso" # bpg importa o qcow2 como disco; file_name precisa de extensao .img
  file_name           = "debian-13-genericcloud-amd64.img"
  url                 = var.debian_cloud_image_url
  overwrite_unmanaged = true
}

resource "proxmox_virtual_environment_vm" "harbor" {
  name        = "harbor"
  node_name   = var.proxmox_node
  description = "Harbor registry (proxy cache + imagens proprias + Trivy) - fora do cluster"
  tags        = ["mgmt", "harbor"]

  cpu {
    cores = var.vcpus
    type  = "host" # passa as flags reais da CPU
  }

  memory {
    dedicated = var.memory
  }

  # Debian genericcloud NAO traz qemu-guest-agent. Com enabled=true o provider
  # espera o agente no Read (timeout padrao 15m) e TRAVA. IP eh estatico e o
  # SSH conecta por IP, entao nao precisamos do agente.
  agent {
    enabled = false
  }

  # Disco de boot. file_id construido a partir dos args CONFIGURADOS do download
  # (conhecidos no plan, ao contrario do `.id` que eh computed) -> recriar/gerir
  # o download nunca forca replace da VM. depends_on garante a ordem em builds do zero.
  disk {
    datastore_id = var.datastore_id
    interface    = "virtio0"
    size         = var.boot_disk_size
    file_id      = "${proxmox_download_file.debian_cloud.datastore_id}:${proxmox_download_file.debian_cloud.content_type}/${proxmox_download_file.debian_cloud.file_name}"
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
      servers = [var.split_dns_ip, var.gateway_ip] # a VM resolve via UDR; nunca via si mesma
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

  depends_on = [proxmox_download_file.debian_cloud]
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
