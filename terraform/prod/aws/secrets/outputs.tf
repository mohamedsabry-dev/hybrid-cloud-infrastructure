# outputs.tf

output "secret_arns" {
  description = "ARNs of created secrets"
  value = {
    proxmox_api             = aws_secretsmanager_secret.proxmox_terraform.arn
    proxmox_ssh_admin       = aws_secretsmanager_secret.proxmox_ssh_admin.arn
    vm_root_password        = aws_secretsmanager_secret.vm_root_password.arn
    break_glass_password    = aws_secretsmanager_secret.gandalf_password.arn
    lxc_root_password       = aws_secretsmanager_secret.lxc_root_password.arn
    ansible_ssh_pubkey      = aws_secretsmanager_secret.ansible_ssh_public_key.arn
    local_runner_ssh_pubkey = aws_secretsmanager_secret.local_runner_ssh_pubkey.arn
  }
}

output "secret_names" {
  description = "Names of created secrets for CLI reference"
  value = {
    proxmox_api             = aws_secretsmanager_secret.proxmox_terraform.name
    proxmox_ssh_admin       = aws_secretsmanager_secret.proxmox_ssh_admin.name
    vm_root_password        = aws_secretsmanager_secret.vm_root_password.name
    break_glass_password    = aws_secretsmanager_secret.gandalf_password.name
    lxc_root_password       = aws_secretsmanager_secret.lxc_root_password.name
    ansible_ssh_pubkey      = aws_secretsmanager_secret.ansible_ssh_public_key.name
    local_runner_ssh_pubkey = aws_secretsmanager_secret.local_runner_ssh_pubkey.name
  }
}
