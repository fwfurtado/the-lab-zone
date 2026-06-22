TF_VAR_proxmox_endpoint="op://homelab/Proxmox Terraform ssh/admin console/admin console URL"
TF_VAR_proxmox_api_token="op://homelab/Proxmox Terraform Token/api-token"
TF_VAR_talos_schematic_id="ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515"

TF_VAR_pdns_api_key="op://homelab/PowerDNS/api-key"
TF_VAR_ssh_public_key="op://homelab/Proxmox Terraform SSH Key/public key"

TF_VAR_garage_access_key="op://the-lab-zone/garage-terraform/key-id"
TF_VAR_garage_secret_key="op://the-lab-zone/garage-terraform/secret"

AWS_ACCESS_KEY_ID="op://homelab/Backblaze/Terraform Key/key-id"
AWS_SECRET_ACCESS_KEY="op://homelab/Backblaze/Terraform Key/application-key"

# ── Harbor (VM, fora do cluster) — vault homelab ─────────────────────────────
TF_VAR_harbor_admin_password="op://homelab/Harbor/admin-password"
TF_VAR_harbor_db_password="op://homelab/Harbor/db-password"

# ── Forgejo (VM, fora do cluster) — vault homelab ────────────────────────────
TF_VAR_forgejo_secret_key="op://homelab/Forgejo/secret-key"
TF_VAR_forgejo_internal_token="op://homelab/Forgejo/internal-token"

# ── ACME (lego DNS-01 Cloudflare) — compartilhado Harbor/Forgejo ─────────────
TF_VAR_cloudflare_dns_api_token="op://homelab/Cloudflare/the-lab.zone"

# ── Docker Hub pull creds p/ proxy cache (usado por `just harbor proxy-init`) ─
DOCKERHUB_PROXY_USERNAME="op://homelab/DockerHub/username"
DOCKERHUB_PROXY_TOKEN="op://homelab/DockerHub/token"

# --- B2 Keys
B2_APPLICATION_KEY_ID="op://Private/Backblaze/Master Key/key-id"
B2_APPLICATION_KEY="op://Private/Backblaze/Master Key/application-key"


# --- Authentik (VM IdP tier-0) ---
TF_VAR_authentik_secret_key="op://homelab/AuthentikVM/secret-key"
TF_VAR_authentik_pg_password="op://homelab/AuthentikVM/pg-password"
TF_VAR_authentik_admin_password="op://homelab/AuthentikVM/admin-password"
TF_VAR_authentik_admin_token="op://homelab/AuthentikVM/admin-api-token"
# Backup -> B2 (app key ESCOPADA criada na PARTE 1)
TF_VAR_b2_backup_key_id="op://homelab/B2 Authentik Backup/keyID"
TF_VAR_b2_backup_key="op://homelab/B2 Authentik Backup/applicationKey"

# ── authentik/sso (config OIDC do IdP) ──
TF_VAR_authentik_url=https://auth.mgmt.the-lab.zone
TF_VAR_authentik_token="op://homelab/AuthentikVM/admin-api-token"

# client_secret por app (mesmo item lido pelo ESO no cluster)
TF_VAR_oidc_secret_argocd="op://the-lab-zone/oidc-argocd/client_secret"
TF_VAR_oidc_secret_grafana="op://the-lab-zone/oidc-grafana/client_secret"
TF_VAR_oidc_secret_open_webui="op://the-lab-zone/oidc-open-webui/client_secret"
TF_VAR_oidc_secret_langfuse="op://the-lab-zone/oidc-langfuse/client_secret"
TF_VAR_oidc_secret_harbor="op://the-lab-zone/oidc-harbor/client_secret"
TF_VAR_oidc_secret_forgejo="op://the-lab-zone/oidc-forgejo/client_secret"
