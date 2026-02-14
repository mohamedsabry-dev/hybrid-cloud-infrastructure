resource "aws_secretsmanager_secret" "proxmox_terraform" {
  name        = "dev/proxmox/terraform-token"
  description = "Proxmox API token for Terraform (tf_dev@pve)"

  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
    Purpose     = "proxmox-automation"
  }
}

resource "aws_secretsmanager_secret_version" "proxmox_terraform" {
  secret_id = aws_secretsmanager_secret.proxmox_terraform.id
  secret_string = jsonencode({
    token_id     = "tf_dev@pve!terraform"
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
  name        = "dev/proxmox/ssh-admin-password"
  description = "Proxmox admin_dev SSH password for Terraform provider (host access)"

  tags = {
    Environment = "dev"
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
# Golden Image VM Root Password
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "golden_image_root" {
  name        = "dev/proxmox/golden-image-root-password"
  description = "Root password for Golden Image VMs"

  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
    Purpose     = "golden-image"
  }
}

resource "aws_secretsmanager_secret_version" "golden_image_root" {
  secret_id     = aws_secretsmanager_secret.golden_image_root.id
  secret_string = "REPLACE_ME"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

#-------------------------------------------------------------------------------
# Proxmox Root SSH Password (for Terraform provider SSH access)
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "proxmox_root" {
  name        = "dev/proxmox/root-password"
  description = "Proxmox root SSH password for Terraform provider"

  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
    Purpose     = "proxmox-automation"
  }
}

resource "aws_secretsmanager_secret_version" "proxmox_root" {
  secret_id     = aws_secretsmanager_secret.proxmox_root.id
  secret_string = "REPLACE_ME"

  lifecycle {
    ignore_changes = [secret_string]
  }
}
