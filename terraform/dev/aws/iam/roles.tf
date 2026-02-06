# IAM roles and users
# IAM module for dev environment
# - Creates plan-cross-dev user (ReadOnly + TerraformStatePlanOnly)
# - Creates GitHubActions-Infrastructure-dev role (PowerUserAccess + SecurityBoundary)
# - State stored in prod account S3 bucket under dev/*



# =============================================================================
# Data Sources
# =============================================================================

data "aws_caller_identity" "current" {}

# Reference the existing OIDC provider (created by bootstrap-dev.yaml)
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# =============================================================================
# 1. Plan-Only IAM User (for local terraform plan on dev + prod)
# =============================================================================
resource "aws_iam_user" "plan_cross" {
  name = "plan-cross-dev"
  tags = local.tags
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
  name        = "GitHubActions-Infrastructure-dev"
  description = "Role for GitHub Actions to deploy infrastructure - no IAM mutation allowed"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github.arn
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
