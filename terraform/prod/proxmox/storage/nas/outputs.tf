#===============================================================================
# Storage Outputs
#===============================================================================

output "nas_iso_id" {
  description = "Storage ID for ISO images and container templates"
  value       = proxmox_virtual_environment_storage_nfs.nas_iso.id
}

output "nas_data_id" {
  description = "Storage ID for VM images and container rootfs"
  value       = proxmox_virtual_environment_storage_nfs.nas_data.id
}

output "backups_id" {
  description = "Storage ID for vzdump backups"
  value       = proxmox_virtual_environment_storage_nfs.backups.id
}
