# IAM roles for prod environment
# - Creates GitHubActions-Infrastructure-prod role (PowerUserAccess + SecurityBoundary)


# =============================================================================
# Locals
# =============================================================================

locals {
  # Hardcoded to ensure resources are always created in prod account
  # regardless of which credentials are used for planning
  oidc_provider_arn = "arn:aws:iam::${var.prod_account_id}:oidc-provider/token.actions.githubusercontent.com"
}

# =============================================================================
# Infrastructure Role (for GitHub Actions - can apply infra, no IAM)
# =============================================================================
resource "aws_iam_role" "github_actions_infrastructure" {
  name                 = "GitHubActions-Infrastructure-prod"
  description          = "Role for GitHub Actions to deploy infrastructure - no IAM mutation allowed"
  permissions_boundary = "arn:aws:iam::${var.prod_account_id}:policy/TerraformPermissionsBoundary"

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
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/prod"
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
  policy_arn = aws_iam_policy.terraform_state_prod.arn
}

resource "aws_iam_role_policy_attachment" "infra_role_power_user" {
  role       = aws_iam_role.github_actions_infrastructure.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy_attachment" "infra_role_security_boundary" {
  role       = aws_iam_role.github_actions_infrastructure.name
  policy_arn = aws_iam_policy.security_boundary_prod.arn
}
