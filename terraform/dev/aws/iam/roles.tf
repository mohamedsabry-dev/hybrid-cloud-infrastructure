# IAM roles and users
# IAM module for dev environment
# - Creates plan-cross-dev user (ReadOnly + TerraformStatePlanOnly)
# - Creates GitHubActions-Infrastructure-dev role (PowerUserAccess + SecurityBoundary)
# - State stored in prod account S3 bucket under dev/*



# =============================================================================
# Locals
# =============================================================================

locals {
  # Hardcoded to ensure resources are always created in dev account
  # regardless of which credentials are used for planning
  oidc_provider_arn = "arn:aws:iam::${var.dev_account_id}:oidc-provider/token.actions.githubusercontent.com"
}

# =============================================================================
# 1. Plan-Only IAM User (for local terraform plan on dev + prod)
# =============================================================================
resource "aws_iam_user" "plan_cross" {
  name                 = "plan-cross-dev"
  permissions_boundary = "arn:aws:iam::${var.dev_account_id}:policy/TerraformPermissionsBoundary"
  tags                 = local.tags
}

resource "aws_iam_user_policy_attachment" "plan_cross_state" {
  user       = aws_iam_user.plan_cross.name
  policy_arn = aws_iam_policy.terraform_state_plan_only.arn
}

resource "aws_iam_user_policy_attachment" "plan_cross_readonly" {
  user       = aws_iam_user.plan_cross.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# =============================================================================
# 2. Infrastructure Role (for GitHub Actions - can apply infra, no IAM)
# =============================================================================
resource "aws_iam_role" "github_actions_infrastructure" {
  name                 = "GitHubActions-Infrastructure-dev"
  description          = "Role for GitHub Actions to deploy infrastructure - no IAM mutation allowed"
  permissions_boundary = "arn:aws:iam::${var.dev_account_id}:policy/TerraformPermissionsBoundary"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/dev"
          }
        }
      }
    ]
  })

  tags = local.tags
}

# Attach policies to Infrastructure Role
resource "aws_iam_role_policy_attachment" "infra_role_tf_state" {
  role       = aws_iam_role.github_actions_infrastructure.name
  policy_arn = aws_iam_policy.terraform_state_dev.arn
}

resource "aws_iam_role_policy_attachment" "infra_role_power_user" {
  role       = aws_iam_role.github_actions_infrastructure.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy_attachment" "infra_role_security_boundary" {
  role       = aws_iam_role.github_actions_infrastructure.name
  policy_arn = aws_iam_policy.security_boundary_dev.arn
}
