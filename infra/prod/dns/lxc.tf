resource "proxmox_download_file" "debian_template" {
  node_name           = "pve"
  datastore_id        = "local"
  content_type        = "vztmpl"
  url                 = "http://download.proxmox.com/images/system/debian-13-standard_13.1-2_amd64.tar.zst"
  overwrite_unmanaged = true
}

resource "proxmox_virtual_environment_container" "dns" {
  node_name     = "pve"
  description   = "PowerDNS autoritativo - the-lab.zone (plano de gestao)"
  tags          = ["mgmt", "dns"]
  unprivileged  = true
  start_on_boot = true

  cpu { cores = 1 }
  memory { dedicated = 512 }

  disk {
    datastore_id = "local-nvme"
    size         = 4
  }

  operating_system {
    template_file_id = proxmox_download_file.debian_template.id
    type             = "debian"
  }

  initialization {
    hostname = "dns"
    ip_config {
      ipv4 {
        address = "${var.dns_ip}/21"
        gateway = var.gateway_ip
      }
    }
    dns {
      servers = [var.gateway_ip] # a LXC resolve via UDR; nunca via si mesma
    }
    user_account {
      keys = [var.ssh_public_key] # root com sua chave (1Password SSH agent)
    }
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }
}

# Provisionamento do PowerDNS via SSH (agent do 1Password funciona com agent=true)
resource "terraform_data" "pdns_provision" {
  depends_on = [proxmox_virtual_environment_container.dns]

  # re-provisiona quando QUALQUER coisa no script muda:
  triggers_replace = [sha1(join("\n", local.pdns_script))]

  connection {
    type  = "ssh"
    host  = var.dns_ip
    user  = "root"
    agent = true
  }

  provisioner "remote-exec" {
    inline = local.pdns_script
  }
}
