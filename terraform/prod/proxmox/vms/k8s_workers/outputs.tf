output "k8s_workers" {
  description = "K8s Worker VMs information"
  value = {
    worker1 = {
      vm_id = proxmox_virtual_environment_vm.k8s_worker1.vm_id
      name  = var.k8s_worker1.name
      ip    = var.k8s_worker1.ip
    }
    worker2 = {
      vm_id = proxmox_virtual_environment_vm.k8s_worker2.vm_id
      name  = var.k8s_worker2.name
      ip    = var.k8s_worker2.ip
    }
    worker3 = {
      vm_id = proxmox_virtual_environment_vm.k8s_worker3.vm_id
      name  = var.k8s_worker3.name
      ip    = var.k8s_worker3.ip
    }
  }
}
