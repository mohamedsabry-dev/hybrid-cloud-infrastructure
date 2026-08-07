output "jenkins_masters" {
  description = "jenkins master VMs information"
  value = {
    master1 = {
      vm_id      = proxmox_virtual_environment_vm.jenkins_master1.vm_id
      name       = var.jenkins_master1.name
      ip         = var.jenkins_master1.ip
      storage_ip = var.jenkins_master1.ip2
    }
  }
}
