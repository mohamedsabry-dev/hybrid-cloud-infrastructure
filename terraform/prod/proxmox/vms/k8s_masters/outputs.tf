output "k8s_masters" {
  description = "K8s Control Plane VMs information"
  value = {
    master1 = {
      vm_id = proxmox_virtual_environment_vm.k8s_master1.vm_id
      name  = var.k8s_master1.name
      ip    = var.k8s_master1.ip
    }
    master2 = {
      vm_id = proxmox_virtual_environment_vm.k8s_master2.vm_id
      name  = var.k8s_master2.name
      ip    = var.k8s_master2.ip
    }
    master3 = {
      vm_id = proxmox_virtual_environment_vm.k8s_master3.vm_id
      name  = var.k8s_master3.name
      ip    = var.k8s_master3.ip
    }
  }
}
