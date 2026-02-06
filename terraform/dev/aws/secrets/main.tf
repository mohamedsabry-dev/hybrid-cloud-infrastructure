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
