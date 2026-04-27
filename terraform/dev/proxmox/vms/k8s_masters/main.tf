#===============================================================================
# K8s Control Plane VMs - Clone from Golden Image Template
#===============================================================================

#-------------------------------------------------------------------------------
# K8s Master 1
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "k8s_master1" {
  node_name = var.node_name
  vm_id     = var.k8s_master1.vmid
  name      = var.k8s_master1.name
  tags      = var.tags

  description = "K8s Control Plane Node 1 cloned from ${var.template_name} golden image"

  # Clone from template
  # full=true creates independent copy (safer than linked clone which depends on source template)
  clone {
    vm_id = var.template_vmid
    full  = true
  }

  started         = var.k8s_master1.started
  on_boot         = var.k8s_master1.on_boot
  stop_on_destroy = var.k8s_master1.stop_on_destroy

  startup {
    order      = var.k8s_master1.startup_order
    up_delay   = var.k8s_master1.startup_delay
    down_delay = var.k8s_master1.shutdown_delay
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

  # CPU (sockets=1 standard, type=host for CPU passthrough performance)
  cpu {
    cores   = var.k8s_master1.cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = var.k8s_master1.memory
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
        address = var.k8s_master1.ip
        gateway = var.k8s_master1.gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.search_domain
    }
  }

  network_device {
    bridge  = var.k8s_master1.bridge
    model   = "virtio"
    vlan_id = var.k8s_master1.vlan_id
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
# K8s Master 2
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "k8s_master2" {
  node_name = var.node_name
  vm_id     = var.k8s_master2.vmid
  name      = var.k8s_master2.name
  tags      = var.tags

  description = "K8s Control Plane Node 2 cloned from ${var.template_name} golden image"

  # Clone from template
  # full=true creates independent copy (safer than linked clone which depends on source template)
  clone {
    vm_id = var.template_vmid
    full  = true
  }

  started         = var.k8s_master2.started
  on_boot         = var.k8s_master2.on_boot
  stop_on_destroy = var.k8s_master2.stop_on_destroy

  startup {
    order      = var.k8s_master2.startup_order
    up_delay   = var.k8s_master2.startup_delay
    down_delay = var.k8s_master2.shutdown_delay
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
      read                = 30
      read_burstable      = 80
      write               = 20
      write_burstable     = 40
    }
  }

  cpu {
    cores   = var.k8s_master2.cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = var.k8s_master2.memory
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
        address = var.k8s_master2.ip
        gateway = var.k8s_master2.gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.search_domain
    }
  }

  network_device {
    bridge  = var.k8s_master2.bridge
    model   = "virtio"
    vlan_id = var.k8s_master2.vlan_id
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
# K8s Master 3
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "k8s_master3" {
  node_name = var.node_name
  vm_id     = var.k8s_master3.vmid
  name      = var.k8s_master3.name
  tags      = var.tags

  description = "K8s Control Plane Node 3 cloned from ${var.template_name} golden image"

  # Clone from template
  # full=true creates independent copy (safer than linked clone which depends on source template)
  clone {
    vm_id = var.template_vmid
    full  = true
  }

  started         = var.k8s_master3.started
  on_boot         = var.k8s_master3.on_boot
  stop_on_destroy = var.k8s_master3.stop_on_destroy

  startup {
    order      = var.k8s_master3.startup_order
    up_delay   = var.k8s_master3.startup_delay
    down_delay = var.k8s_master3.shutdown_delay
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
      read                = 30
      read_burstable      = 80
      write               = 20
      write_burstable     = 40
    }
  }

  cpu {
    cores   = var.k8s_master3.cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = var.k8s_master3.memory
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
        address = var.k8s_master3.ip
        gateway = var.k8s_master3.gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.search_domain
    }
  }

  network_device {
    bridge  = var.k8s_master3.bridge
    model   = "virtio"
    vlan_id = var.k8s_master3.vlan_id
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
