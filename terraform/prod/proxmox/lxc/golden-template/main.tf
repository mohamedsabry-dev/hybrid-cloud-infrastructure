#===============================================================================
# LXC Container - Rocky Linux 10 (Base Template)
# Deploy container from downloaded template for golden image setup
#===============================================================================

resource "proxmox_virtual_environment_container" "lxc_golden" {
  node_name = var.node_name
  vm_id     = var.lxc_container.ctid

  description = "Rocky Linux 10 LXC - Base for golden template"
  tags        = ["lxc", "golden-image", "rocky10"]

  # Don't start automatically on boot
  start_on_boot = false
  started       = true

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

  # CPU
  cpu {
    cores = var.lxc_container.cores
  }

  # Memory
  memory {
    dedicated = var.lxc_container.memory
    swap = var.lxc_container.swap
  }

  # Root filesystem
  disk {
    datastore_id = var.datastore_id
    size         = var.lxc_container.rootfs_size
  }

  # Network
  network_interface {
    name     = "eth0"
    bridge   = var.lxc_container.bridge
    vlan_id  = var.lxc_container.vlan_id
    firewall = false
  }

  # Static IP via Proxmox native LXC config (not cloud-init)
  initialization {
    hostname = var.lxc_container.hostname

    user_account {
      password = var.root_password
      keys     = []
    }

    ip_config {
      ipv4 {
        address = var.lxc_container.ip
        gateway = var.lxc_container.gateway
      }
    }

    dns {
      servers = ["8.8.8.8", "1.1.1.1"]
      domain  = "lab.local"
    }
  }
}


# resource "null_resource" "convert_to_template" {
#  depends_on = [proxmox_virtual_environment_container.lxc_golden]
#
#  provisioner "local-exec" {
#    # This runs a command via SSH on your Proxmox host to finalize the template
#    command = "ssh root@${var.proxmox_host_ip} 'pct template ${var.lxc_container.ctid}'"
#  }
# }
