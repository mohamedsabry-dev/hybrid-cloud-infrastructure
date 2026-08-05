# outputs.tf

output "golden_image_ubuntu" {
  description = "Complete golden image VM information and next steps"
  value = {
    # VM Details
    vm_id  = proxmox_virtual_environment_vm.golden_image_ubuntu.vm_id
    name   = proxmox_virtual_environment_vm.golden_image_ubuntu.name
    node   = proxmox_virtual_environment_vm.golden_image_ubuntu.node_name
    status = proxmox_virtual_environment_vm.golden_image_ubuntu.started ? "running" : "stopped"
    ip     = try(proxmox_virtual_environment_vm.golden_image_ubuntu.ipv4_addresses[1][0], "Not available - agent not running")
    
    # Configuration
    cpu_cores = proxmox_virtual_environment_vm.golden_image_ubuntu.cpu[0].cores
    memory    = proxmox_virtual_environment_vm.golden_image_ubuntu.memory[0].dedicated
    disk_size = proxmox_virtual_environment_vm.golden_image_ubuntu.disk[0].size
    vlan_id   = proxmox_virtual_environment_vm.golden_image_ubuntu.network_device[0].vlan_id
    
    # Commands
    conversion_command = "qm template ${proxmox_virtual_environment_vm.golden_image_ubuntu.vm_id}"
    clone_example      = "qm clone ${proxmox_virtual_environment_vm.golden_image_ubuntu.vm_id} <new-vmid> --name <new-vm-name> --full"
    
    # Next Steps
    setup_instructions = <<-EOT
      1. Access VM console: ${var.proxmox_api_url}
      2. Install Rocky Linux 10.1 from ISO
      3. SSH to VM: ssh root@${try(proxmox_virtual_environment_vm.golden_image_ubuntu.ipv4_addresses[1][0], "<IP>")}
      4. Run cleanup script
      5. Convert to template: qm template ${proxmox_virtual_environment_vm.golden_image_ubuntu.vm_id}
    EOT
  }
}