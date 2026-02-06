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

output "secret_arn" {
  value       = aws_secretsmanager_secret.proxmox_terraform.arn
  description = "ARN of the Proxmox secret"
}

output "secret_name" {
  value       = aws_secretsmanager_secret.proxmox_terraform.name
  description = "Name of the Proxmox secret"
}
