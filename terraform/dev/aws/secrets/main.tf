#-------------------------------------------------------------------------------
# Proxmox API Token
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "proxmox_terraform" {
  name        = var.secrets_config.proxmox_api.name
  description = var.secrets_config.proxmox_api.description
  tags        = var.secrets_config.proxmox_api.tags
}

resource "aws_secretsmanager_secret_version" "proxmox_terraform" {
  secret_id = aws_secretsmanager_secret.proxmox_terraform.id
  secret_string = jsonencode({
    token_id     = var.proxmox_api_credentials.token_id
    token_secret = var.proxmox_api_credentials.token_secret
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

#-------------------------------------------------------------------------------
# Proxmox SSH Admin Password
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "proxmox_ssh_admin" {
  name        = var.secrets_config.proxmox_ssh_admin.name
  description = var.secrets_config.proxmox_ssh_admin.description
  tags        = var.secrets_config.proxmox_ssh_admin.tags
}

resource "aws_secretsmanager_secret_version" "proxmox_ssh_admin" {
  secret_id     = aws_secretsmanager_secret.proxmox_ssh_admin.id
  secret_string = var.secret_initial_value

  lifecycle {
    ignore_changes = [secret_string]
  }
}

#-------------------------------------------------------------------------------
# VM Root Password
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "vm_root_password" {
  name        = var.secrets_config.vm_root_password.name
  description = var.secrets_config.vm_root_password.description
  tags        = var.secrets_config.vm_root_password.tags
}

resource "aws_secretsmanager_secret_version" "vm_root_password" {
  secret_id     = aws_secretsmanager_secret.vm_root_password.id
  secret_string = var.secret_initial_value

  lifecycle {
    ignore_changes = [secret_string]
  }
}

#-------------------------------------------------------------------------------
# Break-Glass User Password
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "break_glass_password" {
  name        = var.secrets_config.break_glass_password.name
  description = var.secrets_config.break_glass_password.description
  tags        = var.secrets_config.break_glass_password.tags
}

resource "aws_secretsmanager_secret_version" "break_glass_password" {
  secret_id     = aws_secretsmanager_secret.break_glass_password.id
  secret_string = var.secret_initial_value

  lifecycle {
    ignore_changes = [secret_string]
  }
}

#-------------------------------------------------------------------------------
# LXC Root Password
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "lxc_root_password" {
  name        = var.secrets_config.lxc_root_password.name
  description = var.secrets_config.lxc_root_password.description
  tags        = var.secrets_config.lxc_root_password.tags
}

resource "aws_secretsmanager_secret_version" "lxc_root_password" {
  secret_id     = aws_secretsmanager_secret.lxc_root_password.id
  secret_string = var.secret_initial_value

  lifecycle {
    ignore_changes = [secret_string]
  }
}

#-------------------------------------------------------------------------------
# Ansible SSH Public Key
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "ansible_ssh_pubkey" {
  name        = var.secrets_config.ansible_ssh_pubkey.name
  description = var.secrets_config.ansible_ssh_pubkey.description
  tags        = var.secrets_config.ansible_ssh_pubkey.tags
}

resource "aws_secretsmanager_secret_version" "ansible_ssh_pubkey" {
  secret_id     = aws_secretsmanager_secret.ansible_ssh_pubkey.id
  secret_string = var.secret_initial_value

  lifecycle {
    ignore_changes = [secret_string]
  }
}

#-------------------------------------------------------------------------------
# Local Runner SSH Public Key
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "local_runner_ssh_pubkey" {
  name        = var.secrets_config.local_runner_ssh_pubkey.name
  description = var.secrets_config.local_runner_ssh_pubkey.description
  tags        = var.secrets_config.local_runner_ssh_pubkey.tags
}

resource "aws_secretsmanager_secret_version" "local_runner_ssh_pubkey" {
  secret_id     = aws_secretsmanager_secret.local_runner_ssh_pubkey.id
  secret_string = var.secret_initial_value

  lifecycle {
    ignore_changes = [secret_string]
  }
}


#-------------------------------------------------------------------------------
# IPA Admin Password
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "ipa_admin_password" {
  name        = var.secrets_config.ipa_admin_password.name
  description = var.secrets_config.ipa_admin_password.description
  tags        = var.secrets_config.ipa_admin_password.tags
}

resource "aws_secretsmanager_secret_version" "ipa_admin_password" {
  secret_id     = aws_secretsmanager_secret.ipa_admin_password.id
  secret_string = var.secret_initial_value

  lifecycle {
    ignore_changes = [secret_string]
  }
}

#-------------------------------------------------------------------------------
# IPA DM Password
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "ipa_dm_password" {
  name        = var.secrets_config.ipa_dm_password.name
  description = var.secrets_config.ipa_dm_password.description
  tags        = var.secrets_config.ipa_dm_password.tags
}

resource "aws_secretsmanager_secret_version" "ipa_dm_password" {
  secret_id     = aws_secretsmanager_secret.ipa_dm_password.id
  secret_string = var.secret_initial_value

  lifecycle {
    ignore_changes = [secret_string]
  }
}
