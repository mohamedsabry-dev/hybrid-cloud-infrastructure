output "nginx" {
  description = "Nginx LXC container information"
  value = {
    container_id = proxmox_virtual_environment_container.nginx.vm_id
    name         = var.nginx.name
    ip           = var.nginx.ip
  }
}
