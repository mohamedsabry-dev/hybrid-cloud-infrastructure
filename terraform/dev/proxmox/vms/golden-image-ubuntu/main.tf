#===============================================================================
# Golden Image VM - ubuntu Linux 10.1 (ISO Installation) #
# Manual installation from ISO, then convert to template #
#===============================================================================

resource "proxmox_virtual_environment_vm" "golden_image_ubuntu" {
  node_name = var.node_name
  vm_id     = var.golden_image_ubuntu.vm_id
  name      = var.golden_image_ubuntu.name
  tags      = var.golden_image_ubuntu.tags
  
  # VM Settings
  description     = var.golden_image_ubuntu.description
  started         = true
  on_boot         = false
  stop_on_destroy = true
  
  # CPU
  cpu {
    cores   = var.golden_image_ubuntu.cpu_cores
    sockets = 1
    type    = "host"
  }
  
  # Memory
  memory {
    dedicated = var.golden_image_ubuntu.memory
  }
  
  # OS Disk
  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.golden_image_ubuntu.disk_size
    ssd          = true
    discard      = "on"
    file_format  = "raw"
  }
  
  # CD-ROM with ubuntu Linux ISO
  cdrom {
    file_id   = var.iso_file_id
    interface = "ide2"
  }
  
  # Network
  network_device {
    bridge  = var.golden_image_ubuntu.bridge
    model   = "virtio"
    vlan_id = var.golden_image_ubuntu.vlan_id
  }
  
  # SCSI Controller
  scsi_hardware = "virtio-scsi-single"
  
  # Boot Order - CD-ROM first for installation, then disk
  boot_order = ["ide2", "scsi0"]
  
  # BIOS
  bios = "seabios"
  
  # Agent (will be installed during setup)
  agent {
    enabled = true
  }
  
  # Operating System Type
  operating_system {
    type = "l26"
  }
  
  # VGA
  vga {
    type   = "std"
    memory = 16
  }

  # Serial console for qm terminal access
  serial_device {
    device = "socket"
  }

  lifecycle {
    ignore_changes = [
      started,
      cdrom,
      boot_order,
    ]
  }
}