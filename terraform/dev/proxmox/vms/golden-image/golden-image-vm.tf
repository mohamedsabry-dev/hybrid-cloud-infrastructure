#===============================================================================
# Golden Image VM - Rocky Linux 10.1 (Cloud Image)
# Uses cloud-init for automated setup
#===============================================================================

#-------------------------------------------------------------------------------
# Fetch Golden Image Root Password from Secrets Manager
#-------------------------------------------------------------------------------
data "aws_secretsmanager_secret_version" "golden_image_root" {
  secret_id = "dev/proxmox/golden-image-root-password"
}

#-------------------------------------------------------------------------------
# Download Rocky Linux Cloud Image
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_download_file" "rocky_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.node_name
  url          = "https://download.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2"
  file_name    = "Rocky-10-GenericCloud-Base.latest.x86_64.qcow2"
}

#-------------------------------------------------------------------------------
# Upload Cloud-Init Config (user_data)
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_file" "cloud_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.node_name

  source_raw {
    data = <<-EOF
#cloud-config
package_update: true
package_upgrade: true

# Set root password
chpasswd:
  list: |
    root:${data.aws_secretsmanager_secret_version.golden_image_root.secret_string}
  expire: false

# Enable root SSH login
ssh_pwauth: true

packages:
  - qemu-guest-agent
  - curl
  - wget
  - vim
  - htop
  - git
  - ca-certificates
  - sudo
  - bash-completion
  - tar
  - unzip
  - openssh-server
  - openssh-clients
  - net-tools
  - traceroute
  - bind-utils
  - tcpdump
  - nmap-ncat
  - iputils
  - iproute

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - systemctl enable sshd
  - sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
  - systemctl restart sshd
  - dnf clean all
  - rm -rf /var/cache/dnf/*
EOF

    file_name = "golden-image-cloud-config.yaml"
  }
}

#-------------------------------------------------------------------------------
# Golden Image VM Resource
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "golden_image" {
  node_name = var.node_name
  vm_id     = var.golden_image_vmid
  name      = "rocky-10-golden"
  tags      = ["golden-image", "template", "rocky"]

  # VM Settings
  description     = "Rocky Linux 10.1 Golden Image - Convert to template after setup"
  started         = true
  on_boot         = false
  stop_on_destroy = true

  # CPU
  cpu {
    cores   = 1
    sockets = 1
    type    = "host"
  }

  # Memory
  memory {
    dedicated = 2048
  }

  # OS Disk - import from downloaded cloud image
  disk {
    datastore_id = "local-lvm"
    file_id      = proxmox_virtual_environment_download_file.rocky_cloud_image.id
    interface    = "scsi0"
    size         = 20
    ssd          = true
    discard      = "on"
  }

  # Cloud-Init configuration
  initialization {
    datastore_id = "local-lvm"

    user_data_file_id = proxmox_virtual_environment_file.cloud_config.id

    ip_config {
      ipv4 {
        address = "10.0.65.99/24"
        gateway = "10.0.65.1"
      }
    }
  }

  # Network - VLAN 65
  network_device {
    bridge  = "vmbr0"
    model   = "virtio"
    vlan_id = 65
  }

  # SCSI Controller
  scsi_hardware = "virtio-scsi-single"

  # Boot Order
  boot_order = ["scsi0"]

  # BIOS
  bios = "seabios"

  # Agent
  agent {
    enabled = true
  }

  # Operating System Type
  operating_system {
    type = "l26"
  }

  # VGA
  vga {
    type = "std"
  }

  lifecycle {
    ignore_changes = [
      started,
    ]
  }
}
