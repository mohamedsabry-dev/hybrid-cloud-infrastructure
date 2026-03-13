#-------------------------------------------------------------------------------
# Vault Unseal Credentials
#-------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "vault_unseal_credentials" {
  name        = "dev/vault/unseal-credentials"
  description = "AWS credentials for Vault KMS auto-unseal"

  tags = {
    Purpose     = "vault-auto-unseal"
    Environment = "dev"
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
