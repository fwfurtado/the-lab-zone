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
  type    = string
  default = "local-nvme"
}

variable "forgejo_ip" {
  type        = string
  default     = "10.40.1.11"
  description = "IP de gestão — TEM que casar com mgmt_records['git'] no módulo dns"
}

variable "gateway_ip" {
  type    = string
  default = "10.40.0.1"
}

variable "vcpus" {
  type    = number
  default = 2
}

variable "memory" {
  type        = number
  default     = 4096
  description = "MB"
}

variable "boot_disk_size" {
  type        = number
  default     = 40
  description = "GB — boot + /srv/forgejo/data (SQLite + repos). Cresce com os repos."
}

variable "debian_cloud_image_url" {
  type    = string
  default = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
}

# ── Forgejo ─────────────────────────────────────────────────────────────────
variable "forgejo_version" {
  type        = string
  default     = "15.0.3"
  description = "LTS (suporte até jul/2027). Imagem codeberg.org/forgejo/forgejo:<tag>"
}

variable "forgejo_ssh_port" {
  type        = string
  default     = "2222"
  description = "Porta SSH do Forgejo no host (22 fica pro sshd da VM, usado no provisionamento)"
}

variable "forgejo_secret_key" {
  type      = string
  sensitive = true
}

variable "forgejo_internal_token" {
  type      = string
  sensitive = true
}

# ── ACME (lego DNS-01 Cloudflare) ───────────────────────────────────────────
variable "cloudflare_dns_api_token" {
  type      = string
  sensitive = true
}

variable "acme_email" {
  type    = string
  default = "admin@the-lab.zone"
}

variable "lego_image" {
  type    = string
  default = "goacme/lego:v5.2.2"
}

variable "acme_propagation_resolver" {
  type        = string
  default     = "1.1.1.1:53"
  description = "Resolver PÚBLICO p/ o self-check do DNS-01. Split-horizon: a vista interna (PowerDNS) não tem o _acme-challenge, que vive na Cloudflare."
}
