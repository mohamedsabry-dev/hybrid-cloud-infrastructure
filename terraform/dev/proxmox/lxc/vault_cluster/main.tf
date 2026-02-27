#===============================================================================
# Vault Cluster LXC Containers
# Clone from golden LXC template and configure for HashiCorp Vault HA cluster
#===============================================================================

#-------------------------------------------------------------------------------
# Vault 1
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_container" "vault1" {
  description = "HashiCorp Vault node 1 - HA cluster member"

  node_name = var.node_name
  vm_id     = var.vault1.ctid

  clone {
    datastore_id = var.disks.os_disk.datastore_id
    vm_id        = var.template_ctid
  }

  disk {
    datastore_id = var.disks.os_disk.datastore_id
    size         = var.disks.os_disk.size
  }

  mount_point {
    volume = var.mount_points.mount_1.volume
    size   = var.mount_points.mount_1.size
    path   = var.mount_points.mount_1.path
  }

  # Container Settings
  started       = var.vault1.started
  start_on_boot = var.vault1.on_boot

  # Setup Startup order
  startup {
    order      = var.vault1.startup_order
    up_delay   = var.vault1.startup_delay
    down_delay = var.vault1.shutdown_delay
  }

  # Container Configuration
  cpu {
    cores = var.vault1.cores
  }

  memory {
    dedicated = var.vault1.memory
  }

  # Network Configuration
  network_interface {
    name     = "eth0"
    bridge   = var.vault1.bridge
    vlan_id  = var.vault1.vlan_id
    firewall = true
  }

  initialization {
    hostname = var.vault1.name

    ip_config {
      ipv4 {
        address = var.vault1.ip
        gateway = var.vault1.gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.search_domain
    }
  }

  lifecycle {
    ignore_changes = [
      started,
      description,
    ]
  }
}

#-------------------------------------------------------------------------------
# Vault 2
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_container" "vault2" {
  description = "HashiCorp Vault node 2 - HA cluster member"

  node_name = var.node_name
  vm_id     = var.vault2.ctid

  clone {
    datastore_id = var.disks.os_disk.datastore_id
    vm_id        = var.template_ctid
  }

  disk {
    datastore_id = var.disks.os_disk.datastore_id
    size         = var.disks.os_disk.size
  }

  mount_point {
    volume = var.mount_points.mount_1.volume
    size   = var.mount_points.mount_1.size
    path   = var.mount_points.mount_1.path
  }

  # Container Settings
  started       = var.vault2.started
  start_on_boot = var.vault2.on_boot

  # Setup Startup order
  startup {
    order      = var.vault2.startup_order
    up_delay   = var.vault2.startup_delay
    down_delay = var.vault2.shutdown_delay
  }

  # Container Configuration
  cpu {
    cores = var.vault2.cores
  }

  memory {
    dedicated = var.vault2.memory
  }

  # Network Configuration
  network_interface {
    name     = "eth0"
    bridge   = var.vault2.bridge
    vlan_id  = var.vault2.vlan_id
    firewall = true
  }

  initialization {
    hostname = var.vault2.name

    ip_config {
      ipv4 {
        address = var.vault2.ip
        gateway = var.vault2.gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.search_domain
    }
  }

  lifecycle {
    ignore_changes = [
      started,
      description,
    ]
  }
}

#-------------------------------------------------------------------------------
# Vault 3
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_container" "vault3" {
  description = "HashiCorp Vault node 3 - HA cluster member"

  node_name = var.node_name
  vm_id     = var.vault3.ctid

  clone {
    datastore_id = var.disks.os_disk.datastore_id
    vm_id        = var.template_ctid
  }

  disk {
    datastore_id = var.disks.os_disk.datastore_id
    size         = var.disks.os_disk.size
  }

  mount_point {
    volume = var.mount_points.mount_1.volume
    size   = var.mount_points.mount_1.size
    path   = var.mount_points.mount_1.path
  }

  # Container Settings
  started       = var.vault3.started
  start_on_boot = var.vault3.on_boot

  # Setup Startup order
  startup {
    order      = var.vault3.startup_order
    up_delay   = var.vault3.startup_delay
    down_delay = var.vault3.shutdown_delay
  }

  # Container Configuration
  cpu {
    cores = var.vault3.cores
  }

  memory {
    dedicated = var.vault3.memory
  }

  # Network Configuration
  network_interface {
    name     = "eth0"
    bridge   = var.vault3.bridge
    vlan_id  = var.vault3.vlan_id
    firewall = true
  }

  initialization {
    hostname = var.vault3.name

    ip_config {
      ipv4 {
        address = var.vault3.ip
        gateway = var.vault3.gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.search_domain
    }
  }

  lifecycle {
    ignore_changes = [
      started,
      description,
    ]
  }
}
