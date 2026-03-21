# IAM managed policies
#
# 1. TerraformState    - Read/write ${environment}/* state in S3 + DynamoDB locking
# 2. SecurityBoundary  - DENY IAM, CloudTrail, Billing
#
# Note: Infrastructure role uses AWS managed PowerUserAccess + SecurityBoundary

# =============================================================================
# 1. Terraform State Policy (S3 + DynamoDB for state files)
# =============================================================================
resource "aws_iam_policy" "terraform_state" {
  name        = "TerraformState-${var.environment}"
  description = "Access to Terraform state bucket and lock table for ${var.environment} environment"

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
        Sid    = "S3ReadWriteState"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::${var.state_bucket_name}/${var.environment}/*"
      },
      {
        Sid    = "DynamoDBStateLocking"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:${var.region}:${var.account_id}:table/${var.lock_table_name}"
      }
    ]
  })

  tags = local.tags
}

# =============================================================================
# 2. Security Boundary Policy (DENY IAM, CloudTrail, Billing + bootstrap protection)
# =============================================================================
resource "aws_iam_policy" "security_boundary" {
  name        = "SecurityBoundary-${var.environment}"
  description = "Prevents IAM mutation, CloudTrail, Billing and bootstrap resource modification"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Block IAM mutation (explicit list, excludes PassRole and read actions)
      {
        Sid    = "DenyIAMMutation"
        Effect = "Deny"
        Action = [
          "iam:CreateUser",
          "iam:DeleteUser",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:AttachUserPolicy",
          "iam:DetachUserPolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:AttachGroupPolicy",
          "iam:DetachGroupPolicy",
          "iam:PutUserPolicy",
          "iam:DeleteUserPolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:PutGroupPolicy",
          "iam:DeleteGroupPolicy",
          "iam:CreateAccessKey",
          "iam:DeleteAccessKey",
          "iam:UpdateAccessKey",
          "iam:CreateLoginProfile",
          "iam:DeleteLoginProfile",
          "iam:UpdateLoginProfile",
          "iam:AddUserToGroup",
          "iam:RemoveUserFromGroup",
          "iam:CreateGroup",
          "iam:DeleteGroup",
          "iam:UpdateGroup",
          "iam:UpdateUser",
          "iam:UpdateRole",
          "iam:SetDefaultPolicyVersion",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:UpdateAssumeRolePolicy",
          "iam:PutRolePermissionsBoundary",
          "iam:DeleteRolePermissionsBoundary"
        ]
        Resource = "*"
      },
      # Allow PassRole only for specific EC2 roles
      {
        Sid      = "AllowPassRoleForEC2"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = [
          "arn:aws:iam::${var.account_id}:role/wireguard-ssm-role-${var.environment}"
        ]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ec2.amazonaws.com"
          }
        }
      },
      # Deny PassRole to any other roles
      {
        Sid      = "DenyPassRoleExceptAllowed"
        Effect   = "Deny"
        Action   = "iam:PassRole"
        NotResource = [
          "arn:aws:iam::${var.account_id}:role/wireguard-ssm-role-${var.environment}"
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
