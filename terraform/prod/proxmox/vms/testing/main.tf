#===============================================================================
# Test VMs - Clone from Golden Image Template
#===============================================================================

#-------------------------------------------------------------------------------
# Test VM 1
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "test1" {
  node_name = var.node_name
  vm_id     = var.test1.vmid
  name      = var.test1.name
  tags      = var.tags

  description = "Test VM 1 cloned from ${var.template_name} golden image"

  # Clone from template
  # full=true creates independent copy (safer than linked clone which depends on source template)
  clone {
    vm_id = var.template_vmid
    full  = true
  }

  started         = var.test1.started
  on_boot         = var.test1.on_boot
  stop_on_destroy = var.test1.stop_on_destroy

  startup {
    order      = var.test1.startup_order
    up_delay   = var.test1.startup_delay
    down_delay = var.test1.shutdown_delay
  }

  disk {
    datastore_id = var.disks.os_disk.datastore_id
    interface    = var.disks.os_disk.interface
    size         = var.disks.os_disk.size
    ssd          = var.disks.os_disk.ssd
    discard      = var.disks.os_disk.discard
    file_format  = var.disks.os_disk.file_format

    speed {
      iops_read           = 500
      iops_read_burstable = 1500
      iops_write          = 300
      iops_write_burstable = 800
      read                = 125
      read_burstable      = 150
      write               = 125
      write_burstable     = 150
    }
  }

  disk {
    datastore_id = var.disks.data_disk.datastore_id
    interface    = var.disks.data_disk.interface
    size         = var.disks.data_disk.size
    ssd          = var.disks.data_disk.ssd
    discard      = var.disks.data_disk.discard
    file_format  = var.disks.data_disk.file_format
  }

  # CPU (sockets=1 standard, type=host for CPU passthrough performance)
  cpu {
    cores   = var.test1.cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = var.test1.memory
  }

  initialization {
    datastore_id = var.disks.os_disk.datastore_id

    user_account {
      keys     = [var.ansible_ssh_public_key]
      username = "root"
      password = var.vm_root_password
    }

    ip_config {
      ipv4 {
        address = var.test1.ip
        gateway = var.test1.gateway
      }
    }

    ip_config {
      ipv4 {
        address = var.test1.ip2
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.search_domain
    }
  }

  # Primary network (Service VLAN)
  network_device {
    bridge  = var.test1.bridge
    model   = "virtio"
    vlan_id = var.test1.vlan_id
  }

  # Storage network (VLAN 40)
  network_device {
    bridge  = var.test1.bridge2
    model   = "virtio"
    vlan_id = var.test1.vlan_id2
  }

  agent {
    enabled = true
  }

  serial_device {
    device = "socket"
  }

  lifecycle {
    # Ignore clone block changes - VMs are already created, changing template_vmid
    # should not trigger recreation of existing VMs
    ignore_changes = [clone]
  }
}

#-------------------------------------------------------------------------------
# Test VM 2
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "test2" {
  node_name = var.node_name
  vm_id     = var.test2.vmid
  name      = var.test2.name
  tags      = var.tags

  description = "Test VM 2 cloned from ${var.template_name} golden image"

  # Clone from template
  # full=true creates independent copy (safer than linked clone which depends on source template)
  clone {
    vm_id = var.template_vmid
    full  = true
  }

  started         = var.test2.started
  on_boot         = var.test2.on_boot
  stop_on_destroy = var.test2.stop_on_destroy

  startup {
    order      = var.test2.startup_order
    up_delay   = var.test2.startup_delay
    down_delay = var.test2.shutdown_delay
  }

  disk {
    datastore_id = var.disks.os_disk.datastore_id
    interface    = var.disks.os_disk.interface
    size         = var.disks.os_disk.size
    ssd          = var.disks.os_disk.ssd
    discard      = var.disks.os_disk.discard
    file_format  = var.disks.os_disk.file_format

    speed {
      iops_read           = 500
      iops_read_burstable = 1500
      iops_write          = 300
      iops_write_burstable = 800
      read                = 125
      read_burstable      = 150
      write               = 125
      write_burstable     = 150
    }
  }

  disk {
    datastore_id = var.disks.data_disk.datastore_id
    interface    = var.disks.data_disk.interface
    size         = var.disks.data_disk.size
    ssd          = var.disks.data_disk.ssd
    discard      = var.disks.data_disk.discard
    file_format  = var.disks.data_disk.file_format
  }

  cpu {
    cores   = var.test2.cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = var.test2.memory
  }

  initialization {
    datastore_id = var.disks.os_disk.datastore_id

    user_account {
      keys     = [var.ansible_ssh_public_key]
      username = "root"
      password = var.vm_root_password
    }

    ip_config {
      ipv4 {
        address = var.test2.ip
        gateway = var.test2.gateway
      }
    }

    ip_config {
      ipv4 {
        address = var.test2.ip2
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.search_domain
    }
  }

  # Primary network (Service VLAN)
  network_device {
    bridge  = var.test2.bridge
    model   = "virtio"
    vlan_id = var.test2.vlan_id
  }

  # Storage network (VLAN 40)
  network_device {
    bridge  = var.test2.bridge2
    model   = "virtio"
    vlan_id = var.test2.vlan_id2
  }

  agent {
    enabled = true
  }

  serial_device {
    device = "socket"
  }

  lifecycle {
    # Ignore clone block changes - VMs are already created, changing template_vmid
    # should not trigger recreation of existing VMs
    ignore_changes = [clone]
  }
}
