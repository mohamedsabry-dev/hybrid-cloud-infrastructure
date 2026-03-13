output "kms_key_id" {
  description = "KMS key ID for Vault unseal"
  value       = aws_kms_key.vault_unseal.key_id
}

output "kms_key_arn" {
  description = "KMS key ARN for Vault unseal"
  value       = aws_kms_key.vault_unseal.arn
}

output "vault_unseal_user_arn" {
  description = "ARN of the Vault unseal IAM user"
  value       = aws_iam_user.vault_unseal.arn
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret containing credentials"
  value       = aws_secretsmanager_secret.vault_unseal_credentials.arn
}
