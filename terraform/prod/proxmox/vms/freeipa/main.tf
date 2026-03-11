#===============================================================================
# FreeIPA VM Clone from Golden Image Template
#===============================================================================


#-------------------------------------------------------------------------------
# Clone VM from Template
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "freeipa" {
  node_name = var.node_name
  vm_id     = var.freeipa.vmid
  name      = var.freeipa.name
  tags      = ["freeipa", "clone", "prod"]

  description = "FreeIPA VM cloned from ${var.template_name} golden image"

  # Clone from template
  clone {
    vm_id = var.template_vmid
    full  = true
  }

  # VM Settings
  started         = var.freeipa.started
  on_boot         = var.freeipa.on_boot
  stop_on_destroy = var.freeipa.stop_on_destroy

  # Setup Startup order
  startup {
    order      = var.freeipa.startup_order
    up_delay   = var.freeipa.startup_delay
    down_delay = var.freeipa.shutdown_delay
  }

  disk {
    datastore_id = var.disks.os_disk.datastore_id
    interface    = var.disks.os_disk.interface
    size         = var.disks.os_disk.size
    ssd          = var.disks.os_disk.ssd
    discard      = var.disks.os_disk.discard
    file_format  = var.disks.os_disk.file_format
  }

  disk {
    datastore_id = var.disks.data_disk.datastore_id
    interface    = var.disks.data_disk.interface
    size         = var.disks.data_disk.size
    ssd          = var.disks.data_disk.ssd
    discard      = var.disks.data_disk.discard
    file_format  = var.disks.data_disk.file_format
  }

  # CPU
  cpu {
    cores   = var.freeipa.cores
    sockets = 1
    type    = "host"
  }

  # Memory
  memory {
    dedicated = var.freeipa.memory
  }

  # Cloud-Init configuration (API only - no snippets).
  initialization {
    datastore_id = var.disks.os_disk.datastore_id

    user_account {
      keys     = [var.ansible_ssh_public_key]
      username = "root"
      password = var.vm_root_password
    }

    ip_config {
      ipv4 {
        address = var.freeipa.ip
        gateway = var.freeipa.gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.search_domain
    }
  }

  # Network
  network_device {
    bridge  = var.freeipa.bridge
    model   = "virtio"
    vlan_id = var.freeipa.vlan_id
  }

  # Agent
  agent {
    enabled = true
  }

  # Serial console for qm terminal access
  serial_device {
    device = "socket"
  }

  lifecycle {
    ignore_changes = []
  }
}
