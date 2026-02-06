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

# Read-only token for terraform plan (spans all environments)
resource "aws_secretsmanager_secret" "proxmox_plan_readonly" {
  name        = "dev/proxmox/plan-readonly-token"
  description = "Proxmox read-only API token for Terraform plan (plan_cross_tf@pve)"

  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
    Purpose     = "proxmox-plan-readonly"
  }
}

resource "aws_secretsmanager_secret_version" "proxmox_plan_readonly" {
  secret_id = aws_secretsmanager_secret.proxmox_plan_readonly.id
  secret_string = jsonencode({
    token_id     = "plan_cross_tf@pve!terraform"
    token_secret = "REPLACE_ME"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
