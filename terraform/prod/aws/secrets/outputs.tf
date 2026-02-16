# outputs.tf

output "secret_arns" {
  description = "ARNs of created secrets"
  value = {
    proxmox_api = aws_secretsmanager_secret.proxmox_terraform.arn
    proxmox_ssh = aws_secretsmanager_secret.proxmox_ssh_admin.arn
    vm_root     = aws_secretsmanager_secret.vm_root_password.arn
    gandalf     = aws_secretsmanager_secret.gandalf_password.arn
  }
}

output "secret_names" {
  description = "Names of created secrets for CLI reference"
  value = {
    proxmox_api = aws_secretsmanager_secret.proxmox_terraform.name
    proxmox_ssh = aws_secretsmanager_secret.proxmox_ssh_admin.name
    vm_root     = aws_secretsmanager_secret.vm_root_password.name
    gandalf     = aws_secretsmanager_secret.gandalf_password.name
  }
}