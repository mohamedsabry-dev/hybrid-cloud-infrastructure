# Shared ISO
resource "proxmox_virtual_environment_storage_nfs" "nas_iso" {
  id      = var.nas_iso.id
  server  = var.nas_iso.server
  export  = var.nas_iso.export
  nodes   = var.nas_iso.nodes
  content = var.nas_iso.content
}

# Dev storage
resource "proxmox_virtual_environment_storage_nfs" "nas_data" {
  id      = var.nas_data.id
  server  = var.nas_data.server
  export  = var.nas_data.export
  nodes   = var.nas_data.nodes
  content = var.nas_data.content

  backups {
    keep_last = var.nas_data.keep_last
  }
}