#===============================================================================
# Outputs for Test VM Clones
#===============================================================================

output "test_vms" {
  description = "Created test VMs"
  value = {
    for key, vm in proxmox_virtual_environment_vm.test_vm : key => {
      vmid      = vm.vm_id
      name      = vm.name
      node      = vm.node_name
      ip        = var.test_vms[key].ip
    }
  }
}

output "verification_commands" {
  description = "Commands to verify cloud-init worked"
  value = <<-EOT
    # SSH into VMs and verify:
    ${join("\n    ", [for key, vm in var.test_vms : "ssh root@${split("/", vm.ip)[0]} 'hostname && cat /var/log/cloud-init-done.log'"])}

    # Expected output for each VM:
    # - Hostname matches VM name
    # - cloud-init-done.log exists with timestamp
  EOT
}

output "cleanup_command" {
  description = "Command to destroy test VMs"
  value       = "terraform destroy -auto-approve"
}
