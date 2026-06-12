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

  # re-provisiona se a config mudar:
  triggers_replace = [var.pdns_api_key, var.dns_ip]

  connection {
    type  = "ssh"
    host  = var.dns_ip
    user  = "root"
    agent = true
  }

  provisioner "remote-exec" {
    inline = [
      "apt-get update -qq",
      "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq pdns-server pdns-backend-sqlite3 sqlite3",
      # schema do SQLite (idempotente):
      "mkdir -p /var/lib/powerdns",
      "[ -f /var/lib/powerdns/pdns.sqlite3 ] || sqlite3 /var/lib/powerdns/pdns.sqlite3 < /usr/share/pdns-backend-sqlite3/schema/schema.sqlite3.sql",
      "chown -R pdns:pdns /var/lib/powerdns",
      # config:
      "cat > /etc/powerdns/pdns.conf <<'EOF'",
      "launch=gsqlite3",
      "gsqlite3-database=/var/lib/powerdns/pdns.sqlite3",
      "local-address=0.0.0.0",
      "api=yes",
      "api-key=${var.pdns_api_key}",
      "webserver=yes",
      "webserver-address=0.0.0.0",
      "webserver-port=8081",
      "webserver-allow-from=10.40.0.0/21",
      "EOF",
      # remove o backend bind default do Debian, se existir:
      "rm -f /etc/powerdns/pdns.d/bind.conf",
      "systemctl restart pdns",
      "systemctl enable pdns",
    ]
  }
}
