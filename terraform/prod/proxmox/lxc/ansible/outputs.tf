output "ansible" {
  description = "Ansible LXC container information"
  value = {
    container_id = proxmox_virtual_environment_container.ansible.vm_id
    name         = var.ansible.name
    ip           = var.ansible.ip
  }
}
