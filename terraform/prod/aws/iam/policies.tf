# IAM managed policies
#
# 1. TerraformState-Prod         - Read/write prod/* state in S3 + DynamoDB locking
# 2. SecurityBoundary-Prod       - DENY IAM, CloudTrail, Billing
#
# Note: Infrastructure role uses AWS managed PowerUserAccess + SecurityBoundary-Prod


# =============================================================================
# 1. Terraform State Policy (S3 + DynamoDB for prod/* state files)
# =============================================================================
resource "aws_iam_policy" "terraform_state_prod" {
  name        = "TerraformState-Prod"
  description = "Access to Terraform state bucket and lock table for prod environment"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ListBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = "arn:aws:s3:::${var.state_bucket_name}"
      },
      {
        Sid    = "S3ReadWriteProdState"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::${var.state_bucket_name}/prod/*"
      },
      {
        Sid    = "DynamoDBStateLocking"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:${var.region}:${var.prod_account_id}:table/${var.lock_table_name}"
      }
    ]
  })

  tags = local.tags
}

# =============================================================================
# 2. Security Boundary Policy (DENY IAM, CloudTrail, Billing)
# =============================================================================
resource "aws_iam_policy" "security_boundary_prod" {
  name        = "SecurityBoundary-Prod"
  description = "Prevents IAM mutation, CloudTrail, Billing and bootstrap resource modification"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Block IAM mutation (except PassRole)
      {
        Sid       = "DenyIAMMutation"
        Effect    = "Deny"
        NotAction = ["iam:PassRole", "iam:GetInstanceProfile"]
        Resource  = "*"
      },
      # Allow PassRole only for specific EC2 roles
      {
        Sid      = "DenyPassRoleExceptAllowed"
        Effect   = "Deny"
        Action   = "iam:PassRole"
        NotResource = [
          "arn:aws:iam::${var.prod_account_id}:role/prod-wireguard-ssm-role"
        ]
      },
      # Block CloudTrail
      {
        Sid      = "DenyCloudTrail"
        Effect   = "Deny"
        Action   = "cloudtrail:*"
        Resource = "*"
      },
      # Block Billing and Cost Management
      {
        Sid    = "DenyBilling"
        Effect = "Deny"
        Action = [
          "aws-portal:*",
          "budgets:*",
          "ce:*",
          "cur:*",
          "purchase-orders:*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.tags
}
