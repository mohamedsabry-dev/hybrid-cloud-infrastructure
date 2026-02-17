variable "secrets" {
  description = "Configuration for AWS Secrets Manager secrets"
  type = map(object({
    name        = string
    description = string
    tags        = map(string)
  }))
  
  default = {
    proxmox_api = {
      name        = "dev/proxmox/terraform-token"
      description = "Proxmox API token for Terraform operations"
      tags = {
        Purpose = "proxmox-automation"
        Environment = "dev"
        ManagedBy   = "terraform"
      }
    }
    proxmox_ssh = {
      name        = "dev/proxmox/ssh-admin-password"
      description = "Proxmox host SSH password for admin_dev user"
      tags = {
        Purpose = "snippets-upload"
        Environment = "dev"
        ManagedBy   = "terraform"
      }
    }
    vm_root = {
      name        = "dev/proxmox/vm-root-password"
      description = "Default root password for cloud-init VM provisioning"
      tags = {
        Purpose = "cloud-init-setup"
        Environment = "dev"
        ManagedBy   = "terraform"
      }
    }
    gandalf = {
      name        = "dev/vm/gandalf-password"
      description = "Emergency break-glass account password for VM recovery"
      tags = {
        Purpose = "break-glass-user"
        Environment = "dev"
        ManagedBy   = "terraform"
      }
    }
    lxc_root = {
      name        = "dev/lxc/root-password"
      description = "Default root password for LXC provisioning"
      tags = {
        Purpose = "cloud-init-setup"
        Environment = "dev"
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
    token_id     = "tf_dev@pve!terraform"
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