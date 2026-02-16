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
    template_file_id = var.template_file
    type             = "centos"
  }

  # CPU
  cpu {
    cores = var.lxc_container.cores
  }

  # Memory
  memory {
    dedicated = var.lxc_container.memory
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

    ip_config {
      ipv4 {
        address = var.lxc_container.ip
        gateway = var.lxc_container.gateway
      }
    }

    dns {
      servers = ["10.0.5.1", "1.1.1.1"]
      domain  = "lab.local"
    }
  }
}

#===============================================================================
# Outputs
#===============================================================================

output "lxc_container" {
  description = "LXC container details"
  value = {
    ctid     = proxmox_virtual_environment_container.lxc_golden.vm_id
    hostname = var.lxc_container.hostname
    ip       = var.lxc_container.ip
    node     = var.node_name
    status   = proxmox_virtual_environment_container.lxc_golden.started ? "running" : "stopped"

    setup_instructions = <<-EOT
    1. SSH to container: ssh root@${split("/", var.lxc_container.ip)[0]}
    2. Install packages manually or run setup script
    3. Stop container: pct stop ${var.lxc_container.ctid}
    4. Convert to template: pct template ${var.lxc_container.ctid}

    Or run the automated script on Proxmox host:
      ./infrastructure/compute/lxc-golden-setup.sh
    EOT

    clone_command      = "pct clone ${var.lxc_container.ctid} <new-ctid> --hostname <name> --full"
    template_command   = "pct template ${var.lxc_container.ctid}"
  }
}
