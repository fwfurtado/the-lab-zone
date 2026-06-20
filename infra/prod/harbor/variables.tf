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
  description = "Datastore dos discos da VM (mesmo NVMe do cluster)"
}

variable "harbor_ip" {
  type        = string
  default     = "10.40.1.10"
  description = "IP de gestão da VM do Harbor — TEM que casar com mgmt_records['harbor'] no módulo dns"
}

variable "gateway_ip" {
  type    = string
  default = "10.40.0.1"
}

variable "vcpus" {
  type    = number
  default = 4
}

variable "memory" {
  type        = number
  default     = 8192
  description = "MB"
}

variable "boot_disk_size" {
  type        = number
  default     = 20
  description = "GB — disco de boot (SO)"
}

variable "data_disk_size" {
  type        = number
  default     = 150
  description = "GB — disco DEDICADO pros blobs/db/redis (montado em /data, virtio1 -> /dev/vdb)"
}

variable "debian_cloud_image_url" {
  type        = string
  default     = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
  description = "Imagem cloud Debian 13 (genericcloud). NÃO é o template -standard usado em LXC."
}

# ── Harbor ──────────────────────────────────────────────────────────────────
variable "harbor_version" {
  type        = string
  default     = "v2.15.1"
  description = "GA mais novo da linha 2.15 (v2.15.2 so existe como rc1). Tem o fix do proxy cache do Docker Hub."
}

variable "harbor_admin_password" {
  type      = string
  sensitive = true
}

variable "harbor_db_password" {
  type      = string
  sensitive = true
}

# ── ACME (lego DNS-01 Cloudflare) ───────────────────────────────────────────
variable "cloudflare_dns_api_token" {
  type        = string
  sensitive   = true
  description = "Token Cloudflare com Zone:DNS:Edit em the-lab.zone (mesmo escopo do cert-manager)"
}

variable "acme_email" {
  type    = string
  default = "admin@the-lab.zone"
}

variable "lego_image" {
  type        = string
  default     = "goacme/lego:v5.2.2"
  description = "lego v5 (CLI: run ANTES das flags). Pin por digest depois de validar."
}

variable "acme_propagation_resolver" {
  type        = string
  default     = "1.1.1.1:53"
  description = "Resolver PÚBLICO p/ o self-check do DNS-01. Split-horizon: a vista interna (PowerDNS) não tem o _acme-challenge, que vive na Cloudflare."
}
