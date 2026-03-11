#===============================================================================
# K8s Worker VMs - Clone from Golden Image Template
#===============================================================================

#-------------------------------------------------------------------------------
# K8s Worker 1
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "k8s_worker1" {
  node_name = var.node_name
  vm_id     = var.k8s_worker1.vmid
  name      = var.k8s_worker1.name
  tags      = ["k8s", "worker", "clone", "prod"]

  description = "K8s Worker Node 1 cloned from ${var.template_name} golden image"

  clone {
    vm_id = var.template_vmid
    full  = true
  }

  started         = var.k8s_worker1.started
  on_boot         = var.k8s_worker1.on_boot
  stop_on_destroy = var.k8s_worker1.stop_on_destroy

  startup {
    order      = var.k8s_worker1.startup_order
    up_delay   = var.k8s_worker1.startup_delay
    down_delay = var.k8s_worker1.shutdown_delay
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

  cpu {
    cores   = var.k8s_worker1.cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = var.k8s_worker1.memory
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
        address = var.k8s_worker1.ip
        gateway = var.k8s_worker1.gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.search_domain
    }
  }

  network_device {
    bridge  = var.k8s_worker1.bridge
    model   = "virtio"
    vlan_id = var.k8s_worker1.vlan_id
  }

  agent {
    enabled = true
  }

  serial_device {
    device = "socket"
  }

  lifecycle {
    ignore_changes = []
  }
}

#-------------------------------------------------------------------------------
# K8s Worker 2
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "k8s_worker2" {
  node_name = var.node_name
  vm_id     = var.k8s_worker2.vmid
  name      = var.k8s_worker2.name
  tags      = ["k8s", "worker", "clone", "prod"]

  description = "K8s Worker Node 2 cloned from ${var.template_name} golden image"

  clone {
    vm_id = var.template_vmid
    full  = true
  }

  started         = var.k8s_worker2.started
  on_boot         = var.k8s_worker2.on_boot
  stop_on_destroy = var.k8s_worker2.stop_on_destroy

  startup {
    order      = var.k8s_worker2.startup_order
    up_delay   = var.k8s_worker2.startup_delay
    down_delay = var.k8s_worker2.shutdown_delay
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

  cpu {
    cores   = var.k8s_worker2.cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = var.k8s_worker2.memory
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
        address = var.k8s_worker2.ip
        gateway = var.k8s_worker2.gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.search_domain
    }
  }

  network_device {
    bridge  = var.k8s_worker2.bridge
    model   = "virtio"
    vlan_id = var.k8s_worker2.vlan_id
  }

  agent {
    enabled = true
  }

  serial_device {
    device = "socket"
  }

  lifecycle {
    ignore_changes = []
  }
}

#-------------------------------------------------------------------------------
# K8s Worker 3
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "k8s_worker3" {
  node_name = var.node_name
  vm_id     = var.k8s_worker3.vmid
  name      = var.k8s_worker3.name
  tags      = ["k8s", "worker", "clone", "prod"]

  description = "K8s Worker Node 3 cloned from ${var.template_name} golden image"

  clone {
    vm_id = var.template_vmid
    full  = true
  }

  started         = var.k8s_worker3.started
  on_boot         = var.k8s_worker3.on_boot
  stop_on_destroy = var.k8s_worker3.stop_on_destroy

  startup {
    order      = var.k8s_worker3.startup_order
    up_delay   = var.k8s_worker3.startup_delay
    down_delay = var.k8s_worker3.shutdown_delay
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

  cpu {
    cores   = var.k8s_worker3.cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = var.k8s_worker3.memory
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
        address = var.k8s_worker3.ip
        gateway = var.k8s_worker3.gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.search_domain
    }
  }

  network_device {
    bridge  = var.k8s_worker3.bridge
    model   = "virtio"
    vlan_id = var.k8s_worker3.vlan_id
  }

  agent {
    enabled = true
  }

  serial_device {
    device = "socket"
  }

  lifecycle {
    ignore_changes = []
  }
}
