output "proxmox_secret_arn" {
  description = "ARN of the Proxmox API token secret"
  value       = aws_secretsmanager_secret.proxmox_api_token.arn
}

output "proxmox_secret_name" {
  description = "Name of the Proxmox API token secret"
  value       = aws_secretsmanager_secret.proxmox_api_token.name
}
