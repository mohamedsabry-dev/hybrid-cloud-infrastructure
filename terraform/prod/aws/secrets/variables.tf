variable "secrets_config" {
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
        Purpose     = "proxmox-automation"
        Environment = "prod"
        ManagedBy   = "terraform"
      }
    }
    proxmox_ssh_admin = {
      name        = "prod/proxmox/ssh-admin-prod-password"
      description = "Proxmox host SSH password for admin_prod user"
      tags = {
        Purpose     = "snippets-upload"
        Environment = "prod"
        ManagedBy   = "terraform"
      }
    }
    vm_root_password = {
      name        = "prod/golden-image/vm-root-password"
      description = "Default root password for cloud-init VM provisioning"
      tags = {
        Purpose     = "cloud-init-setup"
        Environment = "prod"
        ManagedBy   = "terraform"
      }
    }
    break_glass_password = {
      name        = "prod/vm/break-glass-password"
      description = "Emergency break-glass account password for VM recovery"
      tags = {
        Purpose     = "break-glass-user"
        Environment = "prod"
        ManagedBy   = "terraform"
      }
    }
    lxc_root_password = {
      name        = "prod/golden-image/lxc-root-password"
      description = "Default root password for LXC provisioning"
      tags = {
        Purpose     = "lxc-template-root-password"
        Environment = "prod"
        ManagedBy   = "terraform"
      }
    }
    ansible_ssh_pubkey = {
      name        = "prod/ansible/ssh-public-key"
      description = "Ansible VM SSH public key for automated management"
      tags = {
        Purpose     = "ansible-automation"
        Environment = "prod"
        ManagedBy   = "terraform"
      }
    }
    local_runner_ssh_pubkey = {
      name        = "prod/local-runner/ssh-public-key"
      description = "Internal LXC runner SSH public key for Ansible LXC access"
      tags = {
        Purpose     = "gh-runner-ansible-trigger"
        Environment = "prod"
        ManagedBy   = "terraform"
      }
    }
    ipa_admin_password = {
      name        = "prod/freeipa/admin-password"
      description = "IPA Admin password for FreeIPA server"
      tags = {
        Purpose     = "IPA Admin Password for FreeIPA server"
        Environment = "prod"
        ManagedBy   = "terraform"
      }
    }
    ipa_dm_password = {
      name        = "prod/freeipa/dm-password"
      description = "IPA LDAP Password for FreeIPA server"
      tags = {
        Purpose     = "IPA LDAP Password for FreeIPA server"
        Environment = "prod"
        ManagedBy   = "terraform"
      }
    }
    super_bot_keytab = {
      name        = "prod/super_bot/keytab"
      description = "Kerberos keytab for super_bot automation user (base64)"
      tags = {
        Purpose     = "workflow-kerberos-auth"
        Environment = "prod"
        ManagedBy   = "terraform"
      }
    }
    ansible_vault_password = {
      name        = "prod/ansible/vault-password"
      description = "Ansible vault password for decrypting encrypted variables"
      tags = {
        Purpose     = "ansible-vault-decryption"
        Environment = "prod"
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
    token_id     = "tf_prod@pve!terraform"
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
