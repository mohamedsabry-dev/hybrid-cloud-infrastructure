output "secret_arn" {
  value       = aws_secretsmanager_secret.proxmox_terraform.arn
  description = "ARN of the Proxmox secret"
}

output "secret_name" {
  value       = aws_secretsmanager_secret.proxmox_terraform.name
  description = "Name of the Proxmox secret"
}

output "plan_readonly_secret_arn" {
  value       = aws_secretsmanager_secret.proxmox_plan_readonly.arn
  description = "ARN of the Proxmox plan-readonly secret"
}

output "plan_readonly_secret_name" {
  value       = aws_secretsmanager_secret.proxmox_plan_readonly.name
  description = "Name of the Proxmox plan-readonly secret"
}
