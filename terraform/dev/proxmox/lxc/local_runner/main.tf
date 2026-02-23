#===============================================================================
# local_runner LXC Container
# Clone from golden LXC template and configure for local_runner control node 
#===============================================================================

resource "proxmox_virtual_environment_container" "local_runner" {
  description = "local_runner control node for infrastructure automation"

  node_name = var.node_name
  vm_id     = var.local_runner.ctid

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
  started       = var.local_runner.started
  start_on_boot = var.local_runner.on_boot

  # Setup Startup order

  startup {
    order      = var.local_runner.startup_order
    up_delay   = var.local_runner.startup_delay
    down_delay = var.local_runner.shutdown_delay
  }

  # Container Configuration
  cpu {
    cores = var.local_runner.cores
  }

  memory {
    dedicated = var.local_runner.memory
  }

  # Network Configuration
  network_interface {
    name     = "eth0"
    bridge   = var.local_runner.bridge
    vlan_id  = var.local_runner.vlan_id
    firewall = true
  }

  # Cloud-init style initialization (API-only)
  initialization {
    hostname = var.local_runner.name

    user_account {
      username = "root"
      password = var.root_password
    }

    ip_config {
      ipv4 {
        address = var.local_runner.ip
        gateway = var.local_runner.gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.search_domain
    }
  }

  # Prevent Terraform from managing runtime state
  lifecycle {
    ignore_changes = [
      started,
      description,
    ]
  }
}
