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
  tags      = ["freeipa", "clone", "dev"]

  description = "FreeIPA VM cloned from ${var.template_name} golden image"

  # Clone from template
  clone {
    vm_id = var.template_vmid
    full  = true
  }

  # VM Settings
  started         = true
  on_boot         = false
  stop_on_destroy = true

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

  # Cloud-Init configuration (API only - no snippets)
  initialization {
    datastore_id = var.datastore_id

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
    ignore_changes = [started]
  }
}