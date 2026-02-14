resource "aws_secretsmanager_secret" "proxmox_terraform" {
  name        = "prod/proxmox/terraform-token"
  description = "Proxmox API token for Terraform (tf_prod@pve)"

  tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
    Purpose     = "proxmox-automation"
  }
}

resource "aws_secretsmanager_secret_version" "proxmox_terraform" {
  secret_id = aws_secretsmanager_secret.proxmox_terraform.id
  secret_string = jsonencode({
    token_id     = "tf_prod@pve!terraform"
    token_secret = "REPLACE_ME"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

#-------------------------------------------------------------------------------
# Proxmox SSH Admin Password (for snippets upload to Proxmox host)
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "proxmox_ssh_admin" {
  name        = "prod/proxmox/ssh-admin-password"
  description = "Proxmox admin_prod SSH password for Terraform provider (host access)"

  tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
    Purpose     = "proxmox-automation"
  }
}

resource "aws_secretsmanager_secret_version" "proxmox_ssh_admin" {
  secret_id     = aws_secretsmanager_secret.proxmox_ssh_admin.id
  secret_string = "REPLACE_ME"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

#-------------------------------------------------------------------------------
# VM Root Password (for cloud-init when cloning VMs)
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "vm_root_password" {
  name        = "prod/proxmox/vm-root-password"
  description = "Root password for VMs created via cloud-init"

  tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
    Purpose     = "vm-automation"
  }
}

resource "aws_secretsmanager_secret_version" "vm_root_password" {
  secret_id     = aws_secretsmanager_secret.vm_root_password.id
  secret_string = "REPLACE_ME"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

#-------------------------------------------------------------------------------
# Gandalf Break-Glass User Password
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "gandalf_password" {
  name        = "prod/vm/gandalf-password"
  description = "Break-glass user password for emergency VM access"

  tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
    Purpose     = "vm-automation"
  }
}

resource "aws_secretsmanager_secret_version" "gandalf_password" {
  secret_id     = aws_secretsmanager_secret.gandalf_password.id
  secret_string = "REPLACE_ME"

  lifecycle {
    ignore_changes = [secret_string]
  }
}
