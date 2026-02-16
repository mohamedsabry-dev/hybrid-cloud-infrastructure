#===============================================================================
# Test VM Clone from Golden Image Template
#===============================================================================

#-------------------------------------------------------------------------------
# Cloud-Init Config
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_file" "cloud_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.node_name

  source_raw {
    data = <<-EOF
#cloud-config
hostname: ${var.test_vm.name}
fqdn: ${var.test_vm.name}.lab.local

chpasswd:
  list: |
    root:${data.aws_secretsmanager_secret_version.vm_root.secret_string}
  expire: false

network:
  config: disabled

ssh_pwauth: true

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
EOF

    file_name = "cloud-config-${var.test_vm.name}.yaml"
  }
}

#-------------------------------------------------------------------------------
# Clone VM from Template
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "test_vm" {
  node_name = var.node_name
  vm_id     = var.test_vm.vmid
  name      = var.test_vm.name
  tags      = ["test", "clone", "dev"]

  description = "Test VM cloned from ${var.template_name} golden image"

  # Clone from template
  clone {
    vm_id = var.template_vmid
    full  = true
  }

  # VM Settings
  started         = true
  on_boot         = false
  stop_on_destroy = true

  # CPU
  cpu {
    cores   = var.test_vm.cores
    sockets = 1
    type    = "host"
  }

  # Memory
  memory {
    dedicated = var.test_vm.memory
  }

  # Cloud-Init configuration
  initialization {
    datastore_id      = var.datastore_id
    user_data_file_id = proxmox_virtual_environment_file.cloud_config.id

    ip_config {
      ipv4 {
        address = var.test_vm.ip
        gateway = var.test_vm.gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.search_domain
    }
  }

  # Network
  network_device {
    bridge  = var.test_vm.bridge
    model   = "virtio"
    vlan_id = var.test_vm.vlan_id
  }

  # Agent
  agent {
    enabled = true
  }

  lifecycle {
    ignore_changes = [started]
  }

  depends_on = [proxmox_virtual_environment_file.cloud_config]
}