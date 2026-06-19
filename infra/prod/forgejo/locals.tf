locals {
  forgejo_fqdn = "git.mgmt.the-lab.zone"

  forgejo_script = [
    "set -euo pipefail",
    "cloud-init status --wait || true",
    "export DEBIAN_FRONTEND=noninteractive",

    # ── Docker ────────────────────────────────────────────────────────────
    "apt-get update -qq",
    "apt-get install -y -qq ca-certificates curl",
    "curl -fsSL https://get.docker.com | sh",
    "systemctl enable --now docker",

    # ── Layout ────────────────────────────────────────────────────────────
    "mkdir -p /etc/lego /srv/forgejo/data/tls",

    # ── TLS via lego (DNS-01 Cloudflare) ─────────────────────────────────
    "cat > /etc/lego/cloudflare.env <<'EOF'",
    "CF_DNS_API_TOKEN=${var.cloudflare_dns_api_token}",
    "EOF",
    "chmod 600 /etc/lego/cloudflare.env",
    "docker run --rm --env-file /etc/lego/cloudflare.env -v /etc/lego:/etc/lego ${var.lego_image} --accept-tos --email ${var.acme_email} --dns cloudflare --domains ${local.forgejo_fqdn} --path /etc/lego run",
    "install -m 0644 /etc/lego/certificates/${local.forgejo_fqdn}.crt /srv/forgejo/data/tls/forgejo.crt",
    "install -m 0640 /etc/lego/certificates/${local.forgejo_fqdn}.key /srv/forgejo/data/tls/forgejo.key",
    # container roda como uid/gid 1000 (git) e precisa LER cert/chave:
    "chown -R 1000:1000 /srv/forgejo/data/tls",

    # ── Segredos do Forgejo (env_file) ───────────────────────────────────
    "cat > /srv/forgejo/.env <<'EOF'",
    "FORGEJO__security__SECRET_KEY=${var.forgejo_secret_key}",
    "FORGEJO__security__INTERNAL_TOKEN=${var.forgejo_internal_token}",
    "EOF",
    "chmod 600 /srv/forgejo/.env",

    # ── docker-compose (SQLite, TLS proprio, sem reverse proxy) ──────────
    "cat > /srv/forgejo/docker-compose.yml <<'EOF'",
    "services:",
    "  forgejo:",
    "    image: codeberg.org/forgejo/forgejo:${var.forgejo_version}",
    "    container_name: forgejo",
    "    restart: unless-stopped",
    "    env_file: .env",
    "    environment:",
    "      USER_UID: \"1000\"",
    "      USER_GID: \"1000\"",
    "      FORGEJO__database__DB_TYPE: sqlite3",
    "      FORGEJO__database__PATH: /data/forgejo.db",
    "      FORGEJO__server__DOMAIN: ${local.forgejo_fqdn}",
    "      FORGEJO__server__ROOT_URL: https://${local.forgejo_fqdn}/",
    "      FORGEJO__server__PROTOCOL: https",
    "      FORGEJO__server__HTTP_PORT: \"3000\"",
    "      FORGEJO__server__CERT_FILE: /data/tls/forgejo.crt",
    "      FORGEJO__server__KEY_FILE: /data/tls/forgejo.key",
    "      FORGEJO__server__START_SSH_SERVER: \"true\"",
    "      FORGEJO__server__SSH_PORT: \"${var.forgejo_ssh_port}\"",
    "      FORGEJO__server__SSH_LISTEN_PORT: \"22\"",
    "      FORGEJO__service__DISABLE_REGISTRATION: \"true\"",
    "    volumes:",
    "      - /srv/forgejo/data:/data",
    "      - /etc/timezone:/etc/timezone:ro",
    "      - /etc/localtime:/etc/localtime:ro",
    "    ports:",
    "      - \"443:3000\"",
    "      - \"${var.forgejo_ssh_port}:22\"",
    "EOF",
    "cd /srv/forgejo && docker compose up -d",

    # ── Renovação automática ──────────────────────────────────────────────
    "cat > /etc/systemd/system/lego-renew.service <<'EOF'",
    "[Unit]",
    "Description=Renova TLS via lego (DNS-01) e recarrega o Forgejo",
    "After=docker.service",
    "Requires=docker.service",
    "[Service]",
    "Type=oneshot",
    "ExecStart=/usr/bin/docker run --rm --env-file /etc/lego/cloudflare.env -v /etc/lego:/etc/lego ${var.lego_image} --accept-tos --email ${var.acme_email} --dns cloudflare --domains ${local.forgejo_fqdn} --path /etc/lego renew --days 30",
    "ExecStartPost=/usr/bin/install -m 0644 /etc/lego/certificates/${local.forgejo_fqdn}.crt /srv/forgejo/data/tls/forgejo.crt",
    "ExecStartPost=/usr/bin/install -m 0640 /etc/lego/certificates/${local.forgejo_fqdn}.key /srv/forgejo/data/tls/forgejo.key",
    "ExecStartPost=/bin/chown -R 1000:1000 /srv/forgejo/data/tls",
    "ExecStartPost=/bin/sh -c 'cd /srv/forgejo && docker compose restart'",
    "EOF",
    "cat > /etc/systemd/system/lego-renew.timer <<'EOF'",
    "[Unit]",
    "Description=Checagem diaria de renovacao do cert (lego)",
    "[Timer]",
    "OnCalendar=daily",
    "RandomizedDelaySec=3600",
    "Persistent=true",
    "[Install]",
    "WantedBy=timers.target",
    "EOF",
    "systemctl daemon-reload",
    "systemctl enable --now lego-renew.timer",
  ]
}
