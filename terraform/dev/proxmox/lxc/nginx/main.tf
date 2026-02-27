#===============================================================================
# Nginx LXC Container
# Clone from golden LXC template and configure for external nginx reverse proxy
#===============================================================================

resource "proxmox_virtual_environment_container" "nginx" {
  description = "External Nginx reverse proxy for infrastructure"

  node_name = var.node_name
  vm_id     = var.nginx.ctid

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
  started       = var.nginx.started
  start_on_boot = var.nginx.on_boot

  # Setup Startup order
  startup {
    order      = var.nginx.startup_order
    up_delay   = var.nginx.startup_delay
    down_delay = var.nginx.shutdown_delay
  }

  # Container Configuration
  cpu {
    cores = var.nginx.cores
  }

  memory {
    dedicated = var.nginx.memory
  }

  # Network Configuration
  network_interface {
    name     = "eth0"
    bridge   = var.nginx.bridge
    vlan_id  = var.nginx.vlan_id
    firewall = true
  }

  # Cloud-init style initialization (API-only)
  # Note: user_account removed - not supported for cloned LXC (Proxmox API limitation)
  # Password inherited from golden template, SSH keys added manually post-deploy
  initialization {
    hostname = var.nginx.name

    ip_config {
      ipv4 {
        address = var.nginx.ip
        gateway = var.nginx.gateway
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
