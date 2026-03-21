#-------------------------------------------------------------------------------
# Vault Unseal Credentials
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "vault_unseal_credentials" {
  name        = var.vault_unseal_credentials.name
  description = var.vault_unseal_credentials.description

  tags = {
    Purpose     = var.vault_unseal_credentials.purpose
    Environment = var.environment
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
# Vault Unseal Keys
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "vault_unseal_keys" {
  name        = var.vault_unseal_keys.name
  description = var.vault_unseal_keys.description

  tags = {
    Purpose     = var.vault_unseal_keys.purpose
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "vault_unseal_keys" {
  secret_id = aws_secretsmanager_secret.vault_unseal_keys.id

  secret_string = jsonencode({
    key1 = var.key_placeholder
    key2 = var.key_placeholder
    key3 = var.key_placeholder
    key4 = var.key_placeholder
    key5 = var.key_placeholder
    root = var.key_placeholder
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# aws secretsmanager put-secret-value \
#   --secret-id ${var.environment}/vault/unseal-keys \
#   --secret-string '{"key1":"xxx","key2":"xxx","key3":"xxx","key4":"xxx","key5":"xxx","root":"xxx"}'
