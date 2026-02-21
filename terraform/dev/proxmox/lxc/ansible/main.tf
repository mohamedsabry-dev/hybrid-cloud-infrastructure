#===============================================================================
# Ansible LXC Container
# Clone from golden LXC template and configure for Ansible control node
#===============================================================================

resource "proxmox_virtual_environment_container" "ansible" {
  description = "Ansible control node for infrastructure automation"

  node_name = var.node_name
  vm_id     = var.ansible.ctid

  clone {
    datastore_id = var.datastore_id
    vm_id        = var.template_ctid
  }

  # Container Configuration
  cpu {
    cores = var.ansible.cores
  }

  memory {
    dedicated = var.ansible.memory
  }

  # Network Configuration
  network_interface {
    name     = "eth0"
    bridge   = var.ansible.bridge
    vlan_id  = var.ansible.vlan_id
    firewall = true
  }

  # Cloud-init style initialization (API-only)
  initialization {
    hostname = var.ansible.name

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

  # Start on boot
  started       = true
  start_on_boot = true

  # Prevent Terraform from managing runtime state
  lifecycle {
    ignore_changes = [
      started,
      description,
    ]
  }
}
