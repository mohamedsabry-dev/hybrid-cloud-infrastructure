#===============================================================================
# Jenkins Agents VMs - Clone from Golden Image Template
#===============================================================================

#-------------------------------------------------------------------------------
# Jenkins Agent 1
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "jenkins_agent1" {
  node_name = var.node_name
  vm_id     = var.jenkins_agent1.vmid
  name      = var.jenkins_agent1.name
  tags      = var.tags

  description = "jenkins agent Node 1 cloned from ${var.template_name} golden image"

  # Clone from template
  # full=true creates independent copy (safer than linked clone which depends on source template)
  clone {
    vm_id = var.template_vmid
    full  = true
  }

  started         = var.jenkins_agent1.started
  on_boot         = var.jenkins_agent1.on_boot
  stop_on_destroy = var.jenkins_agent1.stop_on_destroy

  startup {
    order      = var.jenkins_agent1.startup_order
    up_delay   = var.jenkins_agent1.startup_delay
    down_delay = var.jenkins_agent1.shutdown_delay
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
    cores   = var.jenkins_agent1.cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = var.jenkins_agent1.memory
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
        address = var.jenkins_agent1.ip
        gateway = var.jenkins_agent1.gateway
      }
    }

    ip_config {
      ipv4 {
        address = var.jenkins_agent1.ip2
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.search_domain
    }
  }

  # Primary network (Service VLAN)
  network_device {
    bridge  = var.jenkins_agent1.bridge
    model   = "virtio"
    vlan_id = var.jenkins_agent1.vlan_id
  }

  # Storage network (VLAN 40)
  network_device {
    bridge  = var.jenkins_agent1.bridge2
    model   = "virtio"
    vlan_id = var.jenkins_agent1.vlan_id2
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
# jenkins agent 2
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "jenkins_agent2" {
  node_name = var.node_name
  vm_id     = var.jenkins_agent2.vmid
  name      = var.jenkins_agent2.name
  tags      = var.tags

  description = "jenkins agent Node 2 cloned from ${var.template_name} golden image"

  # Clone from template
  # full=true creates independent copy (safer than linked clone which depends on source template)
  clone {
    vm_id = var.template_vmid
    full  = true
  }

  started         = var.jenkins_agent2.started
  on_boot         = var.jenkins_agent2.on_boot
  stop_on_destroy = var.jenkins_agent2.stop_on_destroy

  startup {
    order      = var.jenkins_agent2.startup_order
    up_delay   = var.jenkins_agent2.startup_delay
    down_delay = var.jenkins_agent2.shutdown_delay
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

  cpu {
    cores   = var.jenkins_agent2.cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = var.jenkins_agent2.memory
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
        address = var.jenkins_agent2.ip
        gateway = var.jenkins_agent2.gateway
      }
    }

    ip_config {
      ipv4 {
        address = var.jenkins_agent2.ip2
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.search_domain
    }
  }

  # Primary network (Service VLAN)
  network_device {
    bridge  = var.jenkins_agent2.bridge
    model   = "virtio"
    vlan_id = var.jenkins_agent2.vlan_id
  }

  # Storage network (VLAN 40)
  network_device {
    bridge  = var.jenkins_agent2.bridge2
    model   = "virtio"
    vlan_id = var.jenkins_agent2.vlan_id2
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
