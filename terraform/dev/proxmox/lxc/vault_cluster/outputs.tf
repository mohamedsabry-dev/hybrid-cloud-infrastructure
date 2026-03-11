output "vault_cluster" {
  description = "Vault cluster LXC containers information"
  value = {
    vault1 = {
      container_id = proxmox_virtual_environment_container.vault1.vm_id
      name         = var.vault1.name
      ip           = var.vault1.ip
    }
    vault2 = {
      container_id = proxmox_virtual_environment_container.vault2.vm_id
      name         = var.vault2.name
      ip           = var.vault2.ip
    }
    vault3 = {
      container_id = proxmox_virtual_environment_container.vault3.vm_id
      name         = var.vault3.name
      ip           = var.vault3.ip
    }
  }
}
