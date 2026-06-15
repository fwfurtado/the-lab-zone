resource "proxmox_download_file" "talos_iso" {
  node_name    = "pve"
  datastore_id = "local"
  content_type = "iso"
  file_name    = "talos-${var.talos_version}-qemu.iso"
  url          = "https://factory.talos.dev/image/${var.talos_schematic_id}/${var.talos_version}/nocloud-amd64.iso"
}

resource "proxmox_virtual_environment_vm" "talos" {
  for_each  = var.nodes
  name      = "talos-${each.key}"
  node_name = "pve"
  tags      = ["talos", "prod"]

  cpu {
    cores = each.value.vcpus
    type  = "host"                    # importante: Talos/Cilium querem as flags reais da CPU
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = "local-nvme"             # seu storage NVMe no Proxmox
    interface    = "virtio0"
    size         = each.value.disk
    iothread     = true
    discard      = "on"
  }

  # disco de PV — só nasce nos nós que têm pv_disk_size (os workers)
  dynamic "disk" {
    for_each = try(each.value.pv_disk_size, null) != null ? [1] : []
    content {
      datastore_id = "local-nvme"
      interface    = "virtio1"        # ← virtio1 → /dev/vdb
      size         = each.value.pv_disk_size
      iothread     = true
      discard      = "on"
      backup       = false
    }
  }

  network_device {
    bridge = "vmbr0"                  # ajuste se usar VLAN: vlan_id = 30
  }

  cdrom {
    file_id = proxmox_download_file.talos_iso.id
  }

  agent {
    enabled = true                    # o qemu-guest-agent do schematic
  }

  operating_system { type = "l26" }

  lifecycle {
    ignore_changes = [cdrom]          # depois do install, a ISO sai sem o TF brigar
  }
}
