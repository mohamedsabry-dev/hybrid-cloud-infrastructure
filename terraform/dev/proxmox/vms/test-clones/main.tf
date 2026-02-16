#===============================================================================
# Test VM Clone from Golden Image Template
#===============================================================================


#-------------------------------------------------------------------------------
# Clone VM from Template
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "test_vm" {
  node_name = var.node_name
  vm_id     = var.test_vm.vmid
  name      = var.test_vm.name
  tags      = ["test", "clone", "dev"]

  description = "Test VM cloned from ${var.template_name} golden image"

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
    cores   = var.test_vm.cores
    sockets = 1
    type    = "host"
  }

  # Memory
  memory {
    dedicated = var.test_vm.memory
  }

  ##### Cloud-Init configuration #####
  initialization {
    datastore_id      = var.datastore_id
    user_data_file_id = proxmox_virtual_environment_file.cloud_config.id

    ip_config {
      ipv4 {
        address = var.test_vm.ip
        gateway = var.test_vm.gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.search_domain
    }
  }

  # Network
  network_device {
    bridge  = var.test_vm.bridge
    model   = "virtio"
    vlan_id = var.test_vm.vlan_id
  }

  # Agent
  agent {
    enabled = true
  }

  lifecycle {
    ignore_changes = [started]
  }

  depends_on = [proxmox_virtual_environment_file.cloud_config]
}