output "golden_image_vm" {
  description = "Golden image VM details"
  value = {
    vm_id     = proxmox_virtual_environment_vm.golden_image.vm_id
    name      = proxmox_virtual_environment_vm.golden_image.name
    node_name = proxmox_virtual_environment_vm.golden_image.node_name
  }
}

output "cloud_init_status" {
  description = "Cloud-init will install packages and configure the VM automatically"
  value       = "VM starts automatically. Wait for cloud-init to complete, then convert to template."
}
