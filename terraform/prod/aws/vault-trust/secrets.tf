# Secrets Manager - Store IAM credentials for initial Vault setup
# ================================================================

resource "aws_secretsmanager_secret" "vault_aws_creds" {
  name        = "vault/aws-secrets-engine-credentials"
  description = "IAM credentials for Vault AWS secrets engine initial setup"

  tags = {
    Purpose   = "Vault AWS Secrets Engine"
    ManagedBy = "Terraform"
  }
}

resource "aws_secretsmanager_secret_version" "vault_aws_creds" {
  secret_id = aws_secretsmanager_secret.vault_aws_creds.id
  secret_string = jsonencode({
    access_key = aws_iam_access_key.vault_trust.id
    secret_key = aws_iam_access_key.vault_trust.secret
  })
}
