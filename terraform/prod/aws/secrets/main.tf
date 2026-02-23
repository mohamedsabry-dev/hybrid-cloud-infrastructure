#-------------------------------------------------------------------------------
# Proxmox API Token
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "proxmox_terraform" {
  name        = var.secrets.proxmox_api.name
  description = var.secrets.proxmox_api.description
  tags        = var.secrets.proxmox_api.tags
}

resource "aws_secretsmanager_secret_version" "proxmox_terraform" {
  secret_id = aws_secretsmanager_secret.proxmox_terraform.id
  secret_string = jsonencode({
    token_id     = var.proxmox_api_token.token_id
    token_secret = var.proxmox_api_token.token_secret
  })
  
  lifecycle {
    ignore_changes = [secret_string]
  }
}

#-------------------------------------------------------------------------------
# Proxmox SSH Admin Password
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "proxmox_ssh_admin" {
  name        = var.secrets.proxmox_ssh.name
  description = var.secrets.proxmox_ssh.description
  tags        = var.secrets.proxmox_ssh.tags
}

resource "aws_secretsmanager_secret_version" "proxmox_ssh_admin" {
  secret_id     = aws_secretsmanager_secret.proxmox_ssh_admin.id
  secret_string = var.secret_placeholder
  
  lifecycle {
    ignore_changes = [secret_string]
  }
}

#-------------------------------------------------------------------------------
# VM Root Password
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "vm_root_password" {
  name        = var.secrets.vm_root.name
  description = var.secrets.vm_root.description
  tags        = var.secrets.vm_root.tags
}

resource "aws_secretsmanager_secret_version" "vm_root_password" {
  secret_id     = aws_secretsmanager_secret.vm_root_password.id
  secret_string = var.secret_placeholder
  
  lifecycle {
    ignore_changes = [secret_string]
  }
}

#-------------------------------------------------------------------------------
# Gandalf Break-Glass User Password
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "gandalf_password" {
  name        = var.secrets.gandalf.name
  description = var.secrets.gandalf.description
  tags        = var.secrets.gandalf.tags
}

resource "aws_secretsmanager_secret_version" "gandalf_password" {
  secret_id     = aws_secretsmanager_secret.gandalf_password.id
  secret_string = var.secret_placeholder
  
  lifecycle {
    ignore_changes = [secret_string]
  }
}

#-------------------------------------------------------------------------------
# LXC Root Password
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "lxc_root_password" {
  name        = var.secrets.lxc_root.name
  description = var.secrets.lxc_root.description
  tags        = var.secrets.lxc_root.tags
}

resource "aws_secretsmanager_secret_version" "lxc_root_password" {
  secret_id     = aws_secretsmanager_secret.lxc_root_password.id
  secret_string = var.secret_placeholder
  
  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "ansible_ssh_public_key" {
  name        = var.secrets.ansible_ssh.name
  description = var.secrets.ansible_ssh.description
  tags        = var.secrets.ansible_ssh.tags
}

resource "aws_secretsmanager_secret_version" "ansible_ssh_public_key" {
  secret_id     = aws_secretsmanager_secret.ansible_ssh_public_key.id
  secret_string = var.secret_placeholder

  lifecycle {
    ignore_changes = [secret_string]
  }
}

#-------------------------------------------------------------------------------
# Local Runner SSH Public Key
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "local_runner_ssh_pubkey" {
  name        = var.secrets.local_runner_ssh.name
  description = var.secrets.local_runner_ssh.description
  tags        = var.secrets.local_runner_ssh.tags
}

resource "aws_secretsmanager_secret_version" "local_runner_ssh_pubkey" {
  secret_id     = aws_secretsmanager_secret.local_runner_ssh_pubkey.id
  secret_string = var.secret_placeholder

  lifecycle {
    ignore_changes = [secret_string]
  }
}