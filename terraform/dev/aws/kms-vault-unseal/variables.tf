# =============================================================================
# Environment Configuration
# =============================================================================
variable "environment" {
  description = "Environment name (dev/prod)"
  type        = string
  default     = "dev"
}

variable "admin_user" {
  description = "Admin IAM user name for KMS key administration"
  type        = string
  default     = "admin_dev"
}

# =============================================================================
# Secrets Configuration
# =============================================================================
variable "vault_unseal_credentials" {
  description = "Configuration for Vault unseal credentials secret"
  type = object({
    name        = string
    description = string
    purpose     = string
  })
  default = {
    name        = "dev/vault/unseal-credentials"
    description = "AWS credentials for Vault KMS auto-unseal"
    purpose     = "vault-auto-unseal"
  }
}

variable "vault_unseal_keys" {
  description = "Configuration for Vault unseal keys secret"
  type = object({
    name        = string
    description = string
    purpose     = string
  })
  default = {
    name        = "dev/vault/unseal-keys"
    description = "Vault recovery keys and root token from vault operator init"
    purpose     = "vault-manual-unseal"
  }
}

variable "key_placeholder" {
  description = "Placeholder value for Vault unseal keys"
  type        = string
  default     = "Change_Me"
}
