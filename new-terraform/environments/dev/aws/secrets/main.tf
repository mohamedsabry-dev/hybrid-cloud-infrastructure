module "my_lab_secrets" {
  source = "../../../../modules/aws/secrets"

  # 1. Proxmox Token
  proxmox_token_secret_name   = "dev/proxmox/terraform-token"
  proxmox_token_secret_string = jsonencode({
    token_id     = "tf_dev@pve!terraform"
    token_secret = "your-real-token"
  })
  proxmox_token_secret_tags = {
    Environment = "dev"
    Purpose     = "proxmox-api"
  }

  # 2. SSH Admin
  proxmox_ssh_admin_secret_name = "dev/proxmox/ssh-admin-password"
  proxmox_ssh_admin_password    = "your-ssh-password"
  proxmox_ssh_admin_secret_tags = {
    Environment = "dev"
    Purpose     = "host-access"
  }

  # 3. VM Root
  vm_root_password_secret_name = "dev/proxmox/vm-root-password"
  vm_root_password             = "your-root-pass"
  vm_root_password_secret_tags = {
    Environment = "dev"
    Purpose     = "cloud-init"
  }

  # 4. Gandalf
  gandalf_password_secret_name = "dev/vm/gandalf-password"
  gandalf_password             = "your-emergency-pass"
  gandalf_password_secret_tags = {
    Environment = "dev"
    Purpose     = "break-glass"
  }
}

output "proxmox_token_secret_arn" {
  value = module.my_lab_secrets.proxmox_token_secret_arn
}
output "proxmox_ssh_admin_secret_arn" {
  value = module.my_lab_secrets.proxmox_ssh_admin_secret_arn
}
output "vm_root_password_secret_arn" {
  value = module.my_lab_secrets.vm_root_password_secret_arn
}
output "gandalf_password_secret_arn" {
  value = module.my_lab_secrets.gandalf_password_secret_arn
}