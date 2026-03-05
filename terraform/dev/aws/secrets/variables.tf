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
    proxmox_api_root = {
      name        = "dev/proxmox/terraform-token-root"
      description = "Proxmox API token for Terraform Root operations"
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
    local_runner_ssh_pubkey = {
      name        = "dev/local-runner/ssh-public-key"
      description = "Internal LXC runner SSH public key for Ansible LXC access"
      tags = {
        Purpose     = "gh-runner-ansible-trigger"
        Environment = "dev"
        ManagedBy   = "terraform"
      }
    }
    ipa_admin_password = {
      name        = "dev/freeipa/admin-password"
      description = "IPA Admin password for FreeIPA server"
      tags = {
        Purpose     = "IPA Admin Password for FreeIPA server"
        Environment = "dev"
        ManagedBy   = "terraform"
      }
    }
    ipa_dm_password = {
      name        = "dev/freeipa/dm-password"
      description = "IPA LDAP Password for FreeIPA server"
      tags = {
        Purpose     = "IPA LDAP Password for FreeIPA server"
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

variable "proxmox_api_root_credentials" {
  description = "Proxmox API token credentials"
  type = object({
    token_id     = string
    token_secret = string
  })

  default = {
    token_id     = "root@pam!terraform"
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