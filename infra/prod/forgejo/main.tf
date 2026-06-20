# Nome curto = canonico no bpg 0.109 (o longo eh deprecated). Este recurso NAO
# suporta `terraform import`, entao a VM NAO referencia o `.id` dele (que seria
# "known after apply" e forcaria replace). Veja o file_id do disco abaixo.
resource "proxmox_download_file" "debian_cloud" {
  node_name           = var.proxmox_node
  datastore_id        = "local"
  content_type        = "iso"
  file_name           = "debian-13-genericcloud-amd64.img"
  url                 = var.debian_cloud_image_url
  overwrite_unmanaged = true
}

resource "proxmox_virtual_environment_vm" "forgejo" {
  name        = "forgejo"
  node_name   = var.proxmox_node
  description = "Forgejo (git + CI) - fora do cluster - SQLite + push-mirror p/ GitHub (DR)"
  tags        = ["mgmt", "git"]

  cpu {
    cores = var.vcpus
    type  = "host"
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
        address = "${var.forgejo_ip}/21"
        gateway = var.gateway_ip
      }
    }
    dns {
      servers = [var.gateway_ip]
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

resource "terraform_data" "forgejo_provision" {
  depends_on = [proxmox_virtual_environment_vm.forgejo]

  triggers_replace = [sha1(join("\n", local.forgejo_script))]

  connection {
    type  = "ssh"
    host  = var.forgejo_ip
    user  = "root"
    agent = true
  }

  provisioner "remote-exec" {
    inline = local.forgejo_script
  }
}
