# IAM managed policies
#
# 1. TerraformState-Dev         - Read/write dev/* state in S3 + DynamoDB locking
# 2. TerraformStatePlanOnly-Dev - Read-only dev/* and prod/* state (for plan-only user)
# 3. SecurityBoundary-Dev       - DENY IAM, CloudTrail, Billing
#
# Note: Infrastructure role uses AWS managed PowerUserAccess + SecurityBoundary-Dev




# =============================================================================
# 1. Terraform State Policy (S3 + DynamoDB for dev/* state files)
# =============================================================================
resource "aws_iam_policy" "terraform_state_dev" {
  name        = "TerraformState-Dev"
  description = "Access to Terraform state bucket and lock table for dev environment"

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
        Sid    = "S3ReadWriteDevState"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::${var.state_bucket_name}/dev/*"
      },
      {
        Sid    = "DynamoDBStateLocking"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${var.lock_table_name}"
      }
    ]
  })

  tags = local.tags
}

# =============================================================================
# 2. Terraform State Plan-Only (read dev + prod, no apply)
# =============================================================================
resource "aws_iam_policy" "terraform_state_plan_only" {
  name        = "TerraformStatePlanOnly-Dev"
  description = "Read-only state access for terraform plan on both dev and prod (no apply)"

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
        Sid    = "S3ReadStateDevAndProd"
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.state_bucket_name}/dev/*",
          "arn:aws:s3:::${var.state_bucket_name}/prod/*"
        ]
      },
      {
        Sid    = "DynamoDBStateLocking"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${var.lock_table_name}"
      }
    ]
  })

  tags = local.tags
}

# =============================================================================
# 3. Security Boundary Policy (DENY IAM, CloudTrail, Billing + bootstrap protection)
# =============================================================================
resource "aws_iam_policy" "security_boundary_dev" {
  name        = "SecurityBoundary-Dev"
  description = "Prevents IAM mutation, CloudTrail, Billing and bootstrap resource modification"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Block IAM mutation
      {
        Sid      = "DenyIAMMutation"
        Effect   = "Deny"
        Action   = "iam:*"
        Resource = "*"
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
