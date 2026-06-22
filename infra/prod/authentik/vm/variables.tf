variable "proxmox_endpoint" { type = string }

variable "proxmox_api_token" {
  type      = string
  sensitive = true
}

variable "ssh_public_key" {
  type        = string
  description = "Chave pública pro root da VM (provisionamento via 1Password SSH agent)"
}

# ── Proxmox / VM ────────────────────────────────────────────────────────────
variable "proxmox_node" {
  type    = string
  default = "pve"
}

variable "datastore_id" {
  type        = string
  default     = "local-nvme"
  description = "Datastore do disco da VM (mesmo NVMe do cluster)"
}

variable "authentik_ip" {
  type        = string
  default     = "10.40.1.12"
  description = "IP de gestão da VM — TEM que casar com mgmt_records['auth'] no módulo dns"
}

variable "gateway_ip" {
  type    = string
  default = "10.40.0.1"
}

variable "vcpus" {
  type        = number
  default     = 2
  description = "O worker do Authentik pode pesar em CPU; suba pra 4 se notar fila de tasks."
}

variable "memory" {
  type        = number
  default     = 6144
  description = "MB"
}

variable "boot_disk_size" {
  type        = number
  default     = 50
  description = "GB — disco único (SO + PG + redis + media). Sem disco dedicado: identidade é pouco volume."
}

variable "debian_cloud_image_url" {
  type        = string
  default     = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
  description = "Imagem cloud Debian 13 (genericcloud)."
}

# ── Authentik (segredos) ────────────────────────────────────────────────────
# IMPORTANTE: o dump do PG é inútil sem o AUTHENTIK_SECRET_KEY (cifra os secrets
# no DB). Ele vive no 1Password -> coberto. Veja o runbook de restore no BOOTSTRAP.
variable "authentik_secret_key" {
  type        = string
  sensitive   = true
  description = "AUTHENTIK_SECRET_KEY — chave que cifra os secrets no DB. NÃO PERCA (sem ela o backup não restaura)."
}

variable "authentik_pg_password" {
  type      = string
  sensitive = true
}

variable "authentik_admin_email" {
  type    = string
  default = "admin@the-lab.zone"
}

variable "authentik_admin_password" {
  type        = string
  sensitive   = true
  description = "Senha do akadmin (bootstrap na 1a subida)."
}

variable "authentik_admin_token" {
  type        = string
  sensitive   = true
  description = "Token de API do akadmin (bootstrap). É o HANDOFF pro prompt 2 (SSO) — guardado no 1Password."
}

# ── ACME (lego DNS-01 Cloudflare) — mesmo padrão Harbor/Forgejo ─────────────
variable "cloudflare_dns_api_token" {
  type        = string
  sensitive   = true
  description = "Token Cloudflare com Zone:DNS:Edit em the-lab.zone (mesmo escopo do cert-manager)."
}

variable "acme_email" {
  type    = string
  default = "admin@the-lab.zone"
}

variable "lego_image" {
  type        = string
  default     = "goacme/lego:v5.2.2"
  description = "lego v5 (CLI: run/renew ANTES das flags)."
}

variable "acme_propagation_resolver" {
  type        = string
  default     = "1.1.1.1:53"
  description = "Resolver PÚBLICO p/ o self-check do DNS-01 (split-horizon: a vista interna do PowerDNS não tem o _acme-challenge)."
}

# ── Backup (pg_dump -> B2 com app key ESCOPADA) ─────────────────────────────
variable "b2_backup_bucket" {
  type        = string
  default     = "the-lab-zone-authentik-backup"
  description = "Bucket B2 (gerenciado pelo módulo buckets/b2). Offsite, independente do cluster."
}

variable "b2_backup_key_id" {
  type        = string
  sensitive   = true
  description = "keyID da app key ESCOPADA (só este bucket; write/list/delete) — criada à mão no console, guardada no 1Password."
}

variable "b2_backup_key" {
  type      = string
  sensitive = true
}

variable "backup_keep" {
  type        = number
  default     = 14
  description = "Quantos dumps diários manter (local e remoto). O lifecycle do bucket (30d) é só backstop."
}
