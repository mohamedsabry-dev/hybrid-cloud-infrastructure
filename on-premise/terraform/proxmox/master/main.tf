# =============================================================================
# Proxmox Master - Infrastructure VMs
# =============================================================================
# This configuration manages the infrastructure layer VMs on Proxmox Master:
# - TrueNAS SCALE (Storage)
# - pfSense (Firewall/Router)
# - FreeIPA (Identity Management)
# - Proxmox Backup Server
# - Proxmox-Prod (Nested Proxmox for production workloads)
# - Proxmox-DR (Nested Proxmox for disaster recovery - cold standby)
# =============================================================================

# =============================================================================
# Example: TrueNAS SCALE VM
# =============================================================================
# Uncomment and modify when ready to deploy

# resource "proxmox_virtual_environment_vm" "truenas" {
#   name      = "truenas"
#   node_name = var.proxmox_node
#
#   # VM Settings
#   vm_id       = 100
#   description = "TrueNAS SCALE - ZFS Storage Server"
#   tags        = ["infrastructure", "storage"]
#
#   # Hardware
#   cpu {
#     cores = 4
#     type  = "host"
#   }
#
#   memory {
#     dedicated = 8192  # 8GB
#   }
#
#   # Boot disk
#   disk {
#     datastore_id = var.default_storage
#     size         = 32
#     interface    = "scsi0"
#   }
#
#   # Data disk for ZFS pool
#   disk {
#     datastore_id = var.default_storage
#     size         = 500
#     interface    = "scsi1"
#   }
#
#   # Network - Internal only for NFS
#   network_device {
#     bridge = var.network_bridges.internal
#   }
#
#   # Boot from ISO for initial install
#   # cdrom {
#   #   file_id = "local:iso/TrueNAS-SCALE-24.04.0.iso"
#   # }
#
#   operating_system {
#     type = "l26"  # Linux 6.x kernel
#   }
# }

# =============================================================================
# Example: Nested Proxmox-Prod VM
# =============================================================================

# resource "proxmox_virtual_environment_vm" "proxmox_prod" {
#   name      = "proxmox-prod"
#   node_name = var.proxmox_node
#
#   vm_id       = 110
#   description = "Nested Proxmox - Production Workloads"
#   tags        = ["infrastructure", "hypervisor", "production"]
#
#   # Enable nested virtualization
#   cpu {
#     cores = 10
#     type  = "host"  # Required for nested virt
#   }
#
#   memory {
#     dedicated = 26624  # ~26GB
#   }
#
#   # OS Disk
#   disk {
#     datastore_id = var.default_storage
#     size         = 100
#     interface    = "scsi0"
#   }
#
#   # Internal network (VMs will use this)
#   network_device {
#     bridge = var.network_bridges.internal
#   }
#
#   # vMotion network
#   network_device {
#     bridge = var.network_bridges.vmotion
#   }
#
#   operating_system {
#     type = "l26"
#   }
# }
