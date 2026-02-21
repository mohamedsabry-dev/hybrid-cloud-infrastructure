# outputs.tf

output "golden_image" {
  description = "Complete golden image VM information and next steps"
  value = {
    # VM Details
    vm_id  = proxmox_virtual_environment_vm.golden_image.vm_id
    name   = proxmox_virtual_environment_vm.golden_image.name
    node   = proxmox_virtual_environment_vm.golden_image.node_name
    status = proxmox_virtual_environment_vm.golden_image.started ? "running" : "stopped"
    ip     = try(proxmox_virtual_environment_vm.golden_image.ipv4_addresses[1][0], "Not available - agent not running")
    
    # Configuration
    cpu_cores = proxmox_virtual_environment_vm.golden_image.cpu[0].cores
    memory    = proxmox_virtual_environment_vm.golden_image.memory[0].dedicated
    disk_size = proxmox_virtual_environment_vm.golden_image.disk[0].size
    vlan_id   = proxmox_virtual_environment_vm.golden_image.network_device[0].vlan_id
    
    # Commands
    conversion_command = "qm template ${proxmox_virtual_environment_vm.golden_image.vm_id}"
    clone_example      = "qm clone ${proxmox_virtual_environment_vm.golden_image.vm_id} <new-vmid> --name <new-vm-name> --full"
    
    # Next Steps
    setup_instructions = <<-EOT
      1. Access VM console: ${var.proxmox_api_url}
      2. Install Rocky Linux 10.1 from ISO
      3. SSH to VM: ssh root@${try(proxmox_virtual_environment_vm.golden_image.ipv4_addresses[1][0], "<IP>")}
      4. Run cleanup script
      5. Convert to template: qm template ${proxmox_virtual_environment_vm.golden_image.vm_id}
    EOT
  }
}