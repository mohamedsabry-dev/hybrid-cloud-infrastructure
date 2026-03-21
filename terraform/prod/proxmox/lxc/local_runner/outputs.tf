output "local_runner" {
  description = "local_runner LXC container information"
  value = {
    container_id = proxmox_virtual_environment_container.local_runner.vm_id
    name         = var.local_runner.name
    ip           = var.local_runner.ip
  }
}
