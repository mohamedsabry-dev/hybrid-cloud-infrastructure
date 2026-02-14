#===============================================================================
# Golden Image VM - Rocky Linux 10.1 (ISO Installation)
# Manual installation from ISO, then convert to template
#===============================================================================

#-------------------------------------------------------------------------------
# Golden Image VM Resource
#-------------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "golden_image" {
  node_name = var.node_name
  vm_id     = var.golden_image_vmid
  name      = "rocky-10-golden"
  tags      = ["golden-image", "template", "rocky"]

  # VM Settings
  description     = "Rocky Linux 10.1 Golden Image - Install from ISO, run cleanup script, then convert to template"
  started         = true
  on_boot         = false
  stop_on_destroy = true

  # CPU
  cpu {
    cores   = 2
    sockets = 1
    type    = "host"
  }

  # Memory
  memory {
    dedicated = 2048
  }

  # OS Disk - empty disk for installation
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 20
    ssd          = true
    discard      = "on"
    file_format  = "raw"
  }

  # CD-ROM with Rocky Linux ISO
  cdrom {
    enabled   = true
    file_id   = var.iso_file_id
    interface = "ide2"
  }

  # Network - VLAN 65 (temporary IP during setup)
  network_device {
    bridge  = "vmbr0"
    model   = "virtio"
    vlan_id = 65
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

  lifecycle {
    ignore_changes = [
      started,
      cdrom,
      boot_order,
    ]
  }
}
