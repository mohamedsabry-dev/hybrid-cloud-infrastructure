output "test_vms" {
  description = "Test VMs information"
  value = {
    test1 = {
      vm_id      = proxmox_virtual_environment_vm.test1.vm_id
      name       = var.test1.name
      ip         = var.test1.ip
      storage_ip = var.test1.ip2
    }
    test2 = {
      vm_id      = proxmox_virtual_environment_vm.test2.vm_id
      name       = var.test2.name
      ip         = var.test2.ip
      storage_ip = var.test2.ip2
    }
  }
}
