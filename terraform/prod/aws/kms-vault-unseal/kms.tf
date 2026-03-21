data "aws_caller_identity" "current" {}

resource "aws_kms_key" "vault_unseal" {
  description             = "KMS key for Vault auto-unseal"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Root account has full access (required as fallback)
      {
        Sid    = "EnableRootAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      # Key administrators - can manage but not use the key
      {
        Sid    = "AllowKeyAdministration"
        Effect = "Allow"
        Principal = {
          AWS = [
            "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${var.admin_user}",
            "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/GitHubActions-TerraformAdmin-${var.environment}"
          ]
        }
        Action = [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion"
        ]
        Resource = "*"
      },
      # Vault unseal user - can use the key for encrypt/decrypt
      {
        Sid    = "AllowVaultUnsealUsage"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_user.vault_unseal.arn
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name    = "vault-unseal-key"
    Purpose = "vault-auto-unseal"
  }
}

resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/vault-unseal"
  target_key_id = aws_kms_key.vault_unseal.key_id
}
