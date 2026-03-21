output "nas_iso_id" {
  description = "The ID of the NAS ISO storage"
  value       = proxmox_virtual_environment_storage_nfs.nas_iso.id
}

output "nas_data_id" {
  description = "The ID of the NAS data storage"
  value       = proxmox_virtual_environment_storage_nfs.nas_data.id
}

output "backups" {
  description = "The ID of the NAS data storage"
  value       = proxmox_virtual_environment_storage_nfs.backups.id
}
