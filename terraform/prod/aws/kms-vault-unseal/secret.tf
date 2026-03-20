#-------------------------------------------------------------------------------
# Vault Unseal Credentials
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "vault_unseal_credentials" {
  name        = "prod/vault/unseal-credentials"
  description = "AWS credentials for Vault KMS auto-unseal"

  tags = {
    Purpose     = "vault-auto-unseal"
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "vault_unseal_credentials" {
  secret_id = aws_secretsmanager_secret.vault_unseal_credentials.id

  secret_string = jsonencode({
    access_key_id     = aws_iam_access_key.vault_unseal.id
    secret_access_key = aws_iam_access_key.vault_unseal.secret
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

#-------------------------------------------------------------------------------
# Vault Unseal Credentials Keys
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "vault_unseal_keys" {
  name        = "prod/vault/unseal-keys"
  description = "Vault recovery keys and root token from vault operator init"

  tags = {
    Purpose     = "vault-manual-unseal"
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "vault_unseal_keys" {
  secret_id = aws_secretsmanager_secret.vault_unseal_keys.id

  secret_string = jsonencode({
    key1     = var.key_placeholder
    key2     = var.key_placeholder
    key3     = var.key_placeholder
    key4     = var.key_placeholder
    key5     = var.key_placeholder
    root     = var.key_placeholder
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

variable "key_placeholder" {
  default = "Change_Me"
}


# aws secretsmanager put-secret-value \
#   --secret-id prod/vault/unseal-keys \
#   --secret-string '{"key1":"xxx","key2":"xxx","key3":"xxx","key4":"xxx","key5":"xxx","root":"xxx"}'
