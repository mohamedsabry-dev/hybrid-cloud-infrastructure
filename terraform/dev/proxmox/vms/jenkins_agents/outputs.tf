output "jenkins_agents" {
  description = "jenkins agent VMs information"
  value = {
    agent1 = {
      vm_id      = proxmox_virtual_environment_vm.jenkins_agent1.vm_id
      name       = var.jenkins_agent1.name
      ip         = var.jenkins_agent1.ip
      storage_ip = var.jenkins_agent1.ip2
    }
    agent2 = {
      vm_id      = proxmox_virtual_environment_vm.jenkins_agent2.vm_id
      name       = var.jenkins_agent2.name
      ip         = var.jenkins_agent2.ip
      storage_ip = var.jenkins_agent2.ip2
    }
  }
}
