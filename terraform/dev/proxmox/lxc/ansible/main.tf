#===============================================================================
# Ansible LXC Container
# Deploy from golden template with SSH key injection
#===============================================================================

resource "proxmox_virtual_environment_container" "ansible" {
  description = "Ansible control node for infrastructure automation"

  node_name = var.node_name
  vm_id     = var.ansible.ctid
  tags      = ["lxc", "ansible", "infrastructure"]

  # Unprivileged container with nesting
  unprivileged = true

  features {
    nesting = true
  }

  # Operating System Template
  operating_system {
    template_file_id = var.template.file_id
    type             = var.template.os_type
  }

  # Root filesystem
  disk {
    datastore_id = var.disks.os_disk.datastore_id
    size         = var.disks.os_disk.size
  }

  # Additional mount point
  mount_point {
    volume = var.mount_points.mount_1.volume
    size   = var.mount_points.mount_1.size
    path   = var.mount_points.mount_1.path
  }

  # Container Settings
  started       = var.ansible.started
  start_on_boot = var.ansible.on_boot

  # Setup Startup order

  startup {
    order      = var.ansible.startup_order
    up_delay   = var.ansible.startup_delay
    down_delay = var.ansible.shutdown_delay
  }

  # Container Configuration
  cpu {
    cores = var.ansible.cores
  }

  memory {
    dedicated = var.ansible.memory
    swap      = var.ansible.swap
  }

  # Network Configuration
  network_interface {
    name     = "eth0"
    bridge   = var.ansible.bridge
    vlan_id  = var.ansible.vlan_id
    firewall = true
  }

  # Initialization with SSH key injection (supported with template approach)
  initialization {
    hostname = var.ansible.name

    user_account {
      keys     = var.ssh_public_keys
      password = var.root_password
    }

    ip_config {
      ipv4 {
        address = var.ansible.ip
        gateway = var.ansible.gateway
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
