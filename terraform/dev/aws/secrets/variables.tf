variable "secrets_config" {
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
        Purpose     = "proxmox-automation"
        Environment = "dev"
        ManagedBy   = "terraform"
      }
    }
    proxmox_ssh_admin = {
      name        = "dev/proxmox/ssh-admin-dev-password"
      description = "Proxmox host SSH password for admin_dev user"
      tags = {
        Purpose     = "snippets-upload"
        Environment = "dev"
        ManagedBy   = "terraform"
      }
    }
    vm_root_password = {
      name        = "dev/golden-image/vm-root-password"
      description = "Default root password for cloud-init VM provisioning"
      tags = {
        Purpose     = "cloud-init-setup"
        Environment = "dev"
        ManagedBy   = "terraform"
      }
    }
    break_glass_password = {
      name        = "dev/vm/break-glass-password"
      description = "Emergency break-glass account password for VM recovery"
      tags = {
        Purpose     = "break-glass-user"
        Environment = "dev"
        ManagedBy   = "terraform"
      }
    }
    lxc_root_password = {
      name        = "dev/golden-image/lxc-root-password"
      description = "Default root password for LXC provisioning"
      tags = {
        Purpose     = "lxc-template-root-password"
        Environment = "dev"
        ManagedBy   = "terraform"
      }
    }
    ansible_ssh_pubkey = {
      name        = "dev/ansible/ssh-public-key"
      description = "Ansible VM SSH public key for automated management"
      tags = {
        Purpose     = "ansible-automation"
        Environment = "dev"
        ManagedBy   = "terraform"
      }
    }
    mac_mini_ssh_pubkey = {
      name        = "dev/mac-mini/ssh-public-key"
      description = "Mac Mini SSH public key for Ansible CICD management"
      tags = {
        Purpose     = "mac-mini-ansible-cicd"
        Environment = "dev"
        ManagedBy   = "terraform"
      }
    }
  }
}

variable "proxmox_api_credentials" {
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

variable "secret_initial_value" {
  description = "Placeholder value for secrets that will be manually updated"
  type        = string
  default     = "REPLACE_ME"
  sensitive   = true
}