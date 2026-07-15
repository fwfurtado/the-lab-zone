variable "proxmox_endpoint" {
  type = string
}

variable "proxmox_api_token" {
  type      = string
  sensitive = true
}

variable "talos_schematic_id" {
  type = string
}

variable "talos_version" {
  type    = string
  default = "v1.13.4"
}

variable "nodes" {
  type = map(object({
    vcpus            = number
    memory           = number #| MB
    disk             = number #| GB
    boot_datastore   = optional(string)
    pv_disk_size     = optional(number) #| GB
    pv_ssd_disk_size = optional(number) #| GB
  }))

  default = {
    "cp-1"     = { vcpus = 4, memory = 8192, disk = 60, boot_datastore = "cp-nvme" }
    "cp-2"     = { vcpus = 4, memory = 8192, disk = 60, boot_datastore = "cp-nvme" }
    "cp-3"     = { vcpus = 4, memory = 8192, disk = 60, boot_datastore = "cp-nvme" }
    "worker-1" = { vcpus = 8, memory = 32768, disk = 100, pv_disk_size = 400, pv_ssd_disk_size = 200 }
    "worker-2" = { vcpus = 8, memory = 32768, disk = 100, pv_disk_size = 400, pv_ssd_disk_size = 200 }
  }
}
