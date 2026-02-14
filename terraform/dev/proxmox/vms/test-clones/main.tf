#===============================================================================
# Test VM Clones from Golden Image Template
# Tests cloud-init configuration with cloned VMs
#===============================================================================

#-------------------------------------------------------------------------------
# Cloud-Init Config for each VM
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_file" "cloud_config" {
  for_each = var.test_vms

  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.node_name

  source_raw {
    data = <<-EOF
#cloud-config
hostname: ${each.value.name}
fqdn: ${each.value.name}.${var.search_domain}

# Set root password
chpasswd:
  list: |
    root:${local.vm_root_password}
  expire: false

# Disable cloud-init network config (we use Proxmox cloud-init)
network:
  config: disabled

# Enable SSH
ssh_pwauth: true

# Run commands on first boot
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - echo "Cloud-init completed for ${each.value.name}" > /var/log/cloud-init-done.log
  - date >> /var/log/cloud-init-done.log
EOF

    file_name = "cloud-config-${each.value.name}.yaml"
  }
}

#-------------------------------------------------------------------------------
# Clone VMs from Template
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "test_vm" {
  for_each = var.test_vms

  node_name = var.node_name
  vm_id     = each.value.vmid
  name      = each.value.name
  tags      = ["test", "clone", "dev"]

  description = "Test VM cloned from golden image template"

  # Clone from template
  clone {
    vm_id = var.template_vmid
    full  = true
  }

  # VM Settings
  started         = true
  on_boot         = false
  stop_on_destroy = true

  # CPU (override template if needed)
  cpu {
    cores   = each.value.cores
    sockets = 1
    type    = "host"
  }

  # Memory
  memory {
    dedicated = each.value.memory
  }

  # Cloud-Init configuration
  initialization {
    datastore_id = "local-lvm"

    user_data_file_id = proxmox_virtual_environment_file.cloud_config[each.key].id

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = each.value.gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.search_domain
    }
  }

  # Network
  network_device {
    bridge  = "vmbr0"
    model   = "virtio"
    vlan_id = each.value.vlan
  }

  # Agent
  agent {
    enabled = true
  }

  lifecycle {
    ignore_changes = [
      started,
    ]
  }

  depends_on = [proxmox_virtual_environment_file.cloud_config]
}
