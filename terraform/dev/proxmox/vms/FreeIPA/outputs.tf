output "freeipa" {
  description = "freeipa VM information"
  value = {
    vm_id  = proxmox_virtual_environment_vm.freeipa.vm_id
    name   = proxmox_virtual_environment_vm.freeipa.name
    node   = proxmox_virtual_environment_vm.freeipa.node_name
    ip     = var.freeipa.ip
  }
}