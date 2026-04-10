# IAM Resources for Vault AWS Secrets Engine
# ===========================================

#######################################
# IAM User - Vault authenticates to AWS with this
#######################################
resource "aws_iam_user" "vault_trust" {
  name = "vault_trust"
  path = "/system/"

  tags = {
    Purpose   = "Vault AWS Secrets Engine"
    ManagedBy = "Terraform"
  }
}

resource "aws_iam_access_key" "vault_trust" {
  user = aws_iam_user.vault_trust.name
}

#######################################
# User Policy - Allow vault_trust to assume specific roles
#######################################
resource "aws_iam_user_policy" "vault_assume_roles" {
  name = "vault-assume-backup-roles"
  user = aws_iam_user.vault_trust.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = [
        aws_iam_role.etcd_backup.arn,
        # Add more role ARNs here as needed
      ]
    }]
  })
}

#######################################
# IAM Role - etcd backup role (Vault assumes this)
#######################################
resource "aws_iam_role" "etcd_backup" {
  name = "etcd-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { AWS = aws_iam_user.vault_trust.arn }
    }]
  })

  tags = {
    Purpose   = "etcd backup to S3"
    ManagedBy = "Terraform"
  }
}

#######################################
# Role Policy - S3 permissions for etcd backup
#######################################
resource "aws_iam_role_policy" "etcd_backup_s3" {
  name = "etcd-backup-s3-access"
  role = aws_iam_role.etcd_backup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ]
      Resource = [
        "arn:aws:s3:::${aws_s3_bucket.etcd_backup.id}",
        "arn:aws:s3:::${aws_s3_bucket.etcd_backup.id}/*"
      ]
    }]
  })
}
