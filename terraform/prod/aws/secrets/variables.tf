variable "secrets" {
  description = "Configuration for AWS Secrets Manager secrets"
  type = map(object({
    name        = string
    description = string
    tags        = map(string)
  }))
  
  default = {
    proxmox_api = {
      name        = "prod/proxmox/terraform-token"
      description = "Proxmox API token for Terraform operations"
      tags = {
        Purpose = "proxmox-automation"
        Environment = "prod"
        ManagedBy   = "terraform"
      }
    }
    proxmox_ssh = {
      name        = "prod/proxmox/ssh-admin-password"
      description = "Proxmox host SSH password for admin_prod user"
      tags = {
        Purpose = "snippets-upload"
        Environment = "prod"
        ManagedBy   = "terraform"
      }
    }
    vm_root = {
      name        = "prod/proxmox/vm-root-password"
      description = "Default root password for cloud-init VM provisioning"
      tags = {
        Purpose = "cloud-init-setup"
        Environment = "prod"
        ManagedBy   = "terraform"
      }
    }
    gandalf = {
      name        = "prod/vm/gandalf-password"
      description = "Emergency break-glass account password for VM recovery"
      tags = {
        Purpose = "break-glass-user"
        Environment = "prod"
        ManagedBy   = "terraform"
      }
    }
  }
}



variable "proxmox_api_token" {
  description = "Proxmox API token credentials"
  type = object({
    token_id     = string
    token_secret = string
  })
  
  default = {
    token_id     = "tf_prod@pve!terraform"
    token_secret = "REPLACE_ME"
  }
  
  sensitive = true
}


variable "secret_placeholder" {
  description = "Placeholder value for secrets that will be manually updated"
  type        = string
  default     = "REPLACE_ME"
  sensitive   = true
}