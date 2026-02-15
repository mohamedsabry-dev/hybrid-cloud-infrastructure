module "my_lab_secrets" {
  source = "../../modules/secrets"

  # 1. Proxmox Token
  proxmox_token_secret_name   = "dev/proxmox/tf-token"
  proxmox_token_secret_string = jsonencode({
    token_id     = "tf_dev@pve!terraform"
    token_secret = "your-real-token"
  })
  proxmox_token_secret_tags = {
    Environment = "dev"
    Purpose     = "proxmox-api"
  }

  # 2. SSH Admin
  proxmox_ssh_admin_secret_name = "dev/proxmox/ssh-admin"
  proxmox_ssh_admin_password    = "your-ssh-password"
  proxmox_ssh_admin_secret_tags = {
    Environment = "dev"
    Purpose     = "host-access"
  }

  # 3. VM Root
  vm_root_password_secret_name = "dev/vm/root-pass"
  vm_root_password             = "your-root-pass"
  vm_root_password_secret_tags = {
    Environment = "dev"
    Purpose     = "cloud-init"
  }

  # 4. Gandalf
  gandalf_password_secret_name = "dev/vm/gandalf-pass"
  gandalf_password             = "your-emergency-pass"
  gandalf_password_secret_tags = {
    Environment = "dev"
    Purpose     = "break-glass"
  }
}