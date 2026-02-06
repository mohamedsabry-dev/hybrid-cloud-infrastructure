output "secret_arn" {
  value       = aws_secretsmanager_secret.proxmox_terraform.arn
  description = "ARN of the Proxmox secret"
}

output "secret_name" {
  value       = aws_secretsmanager_secret.proxmox_terraform.name
  description = "Name of the Proxmox secret"
}
