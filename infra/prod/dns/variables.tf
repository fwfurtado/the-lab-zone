variable "proxmox_endpoint" { type = string }
variable "proxmox_api_token" {
  type      = string
  sensitive = true
}
variable "pdns_api_key" {
  type      = string
  sensitive = true
}

variable "dns_ip" {
  type        = string
  default     = "10.40.1.53"
  description = "IP do servidor DNS (PowerDNS)"
}

variable "gateway_ip" {
  type        = string
  default     = "10.40.0.1"
  description = "IP do gateway"
}

variable "lab_gateway_lb_ip" {
  type        = string
  default     = "10.40.7.10"
  description = "IP pinado do Gateway (Cilium LB-IPAM) — alvo do wildcard"
}

variable "ssh_public_key" {
  type        = string
  description = "Chave pública pro root da LXC (provisionamento)"
}

variable "mgmt_records" {
  type = map(string)
  default = {
    pve    = "10.40.0.200" # ajuste pros IPs reais
    idrac  = "10.40.0.32"
    nas    = "10.40.1.4"
    pg     = "10.40.1.75"
    dns    = "10.40.1.53"
    harbor = "10.40.1.10"
    git    = "10.40.1.11"
    auth   = "10.40.1.12"
  }
}
