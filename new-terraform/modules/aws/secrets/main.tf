#############################################
resource "aws_secretsmanager_secret" "proxmox_terraform" {
  name        = var.proxmox_token_secret_name
  description = var.proxmox_token_secret_description
  tags        = var.proxmox_token_secret_tags

}
## *** Variables *** ##
variable "proxmox_token_secret_name" {
  type        = string
  description = "Name of the Proxmox API token for Terraform"
}
variable "proxmox_token_secret_description" {
  type        = string
  description = "Description for the Proxmox API token for Terraform"
  default     = "ManagedBy: Terraform - Proxmox API token for Terraform"
}
variable "proxmox_token_secret_tags" {
  type        = map(string)
  description = "Tags to apply to the Proxmox API token for Terraform"
  default     = {
    Environment = ""
    ManagedBy   = "Terraform"
    Purpose     = "terraform-token"
  }
}

######### ********* ********* #########

resource "aws_secretsmanager_secret_version" "proxmox_terraform" {
  secret_id = aws_secretsmanager_secret.proxmox_terraform.id
  secret_string = var.proxmox_token_secret_string

  lifecycle {
    ignore_changes = [secret_string]
  }
}

## *** Variables *** ##
variable "proxmox_token_secret_string" {
  type        = string
  description = "Secret string for the Proxmox API token for Terraform (JSON format)"
  default     = jsonencode({
    token_id     = "REPLACE_ME"
    token_secret = "REPLACE_ME"
  })
  sensitive  = true
}

output "proxmox_token_secret_arn" {
  value       = aws_secretsmanager_secret.proxmox_terraform.arn
  description = "The ARN of the Proxmox token secret"
}

#############################################

#-------------------------------------------------------------------------------
# Proxmox SSH Admin Password (for snippets upload to Proxmox host)
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "proxmox_ssh_admin" {
  name        = var.proxmox_ssh_admin_secret_name
  description = var.proxmox_ssh_admin_secret_description
  tags = var.proxmox_ssh_admin_secret_tags
}

resource "aws_secretsmanager_secret_version" "proxmox_ssh_admin" {
  secret_id     = aws_secretsmanager_secret.proxmox_ssh_admin.id
  secret_string = var.proxmox_ssh_admin_password

  lifecycle {
    ignore_changes = [secret_string]
  }
}

variable "proxmox_ssh_admin_secret_name" {
  type        = string
  description = "Name of the Proxmox SSH admin password secret"
}

variable "proxmox_ssh_admin_secret_description" {
  type        = string
  description = "Description for the Proxmox SSH admin password secret"
  default     = "ManagedBy: Terraform "
}

variable "proxmox_ssh_admin_secret_tags" {
  type        = map(string)
  description = "Tags to apply to the Proxmox SSH admin password secret"
  default
    = {
     Environment = ""
     ManagedBy   = "Terraform"
     Purpose     = "host-access"
    }
}
variable "proxmox_ssh_admin_password" {
  type        = string
  description = "Proxmox admin_dev SSH password for Terraform provider (host access)"
  default     = "REPLACE_ME"
  sensitive   = true
}

output "proxmox_ssh_admin_secret_arn" {
  value       = aws_secretsmanager_secret.proxmox_ssh_admin.arn
  description = "The ARN of the Proxmox SSH admin password secret"
}

################

#-------------------------------------------------------------------------------
# VM Root Password (for cloud-init when cloning VMs)
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "vm_root_password" {
  name        = var.vm_root_password_secret_name
  description = var.vm_root_password_secret_description
  tags        = var.vm_root_password_secret_tags
}

resource "aws_secretsmanager_secret_version" "vm_root_password" {
  secret_id     = aws_secretsmanager_secret.vm_root_password.id
  secret_string = var.vm_root_password

  lifecycle {
    ignore_changes = [secret_string]
  }
}

variable "vm_root_password" {
  type        = string
  description = "Root password for VMs created via cloud-init"
  default     = "REPLACE_ME"
  sensitive   = true
}

variable "vm_root_password_secret_name" {
  type        = string
  description = "Name of the VM root password secret"
}

variable "vm_root_password_secret_description" {
  type        = string
  description = "Description for the VM root password secret"
  default     = "ManagedBy: Terraform - Root password for VMs created via cloud-init"
}

variable "vm_root_password_secret_tags" {
  type        = map(string)
  description = "Tags to apply to the VM root password secret"
  default     = {
    Environment = ""
    ManagedBy   = "Terraform"
    Purpose     = "cloud-init"
  }
}

output "vm_root_password_secret_arn" {
  value       = aws_secretsmanager_secret.vm_root_password.arn
  description = "The ARN of the VM root password secret"
}


###############

#-------------------------------------------------------------------------------
# Gandalf Break-Glass User Password
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "gandalf_password" {
  name        = var.gandalf_password_secret_name
  description = var.gandalf_password_secret_description
  tags        = var.gandalf_password_secret_tags
}

resource "aws_secretsmanager_secret_version" "gandalf_password" {
  secret_id     = aws_secretsmanager_secret.gandalf_password.id
  secret_string = var.gandalf_password

  lifecycle {
    ignore_changes = [secret_string]
  }
}

variable "gandalf_password" {
  type        = string
  description = "Break-glass user password for emergency VM access"
  default     = "REPLACE_ME"
  sensitive   = true
}

variable "gandalf_password_secret_name" {
  type        = string
  description = "Name of the Gandalf break-glass password secret"
}

variable "gandalf_password_secret_description" {
  type        = string
  description = "Description for the Gandalf break-glass password secret"
  default     = "ManagedBy: Terraform - Break-glass user password for emergency VM access"
}

variable "gandalf_password_secret_tags" {
  type        = map(string)
  description = "Tags to apply to the Gandalf break-glass password secret"
  default     = {
    Environment = ""
    ManagedBy   = "Terraform"
    Purpose     = "break-glass"
  }
}

output "gandalf_password_secret_arn" {
  value       = aws_secretsmanager_secret.gandalf_password.arn
  description = "The ARN of the Gandalf break-glass password secret"
}