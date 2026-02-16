output "test_vm" {
  description = "Test VM information"
  value = {
    vm_id  = proxmox_virtual_environment_vm.test_vm.vm_id
    name   = proxmox_virtual_environment_vm.test_vm.name
    node   = proxmox_virtual_environment_vm.test_vm.node_name
    ip     = var.test_vm.ip
    ssh    = "ssh root@${split("/", var.test_vm.ip)[0]}"
  }
}