# Outputs for policy and role ARNs

# =============================================================================
# Policy ARNs
# =============================================================================
output "terraform_state_policy_arn" {
  description = "ARN of the Terraform State policy (read/write dev)"
  value       = aws_iam_policy.terraform_state_dev.arn
}

output "terraform_state_plan_only_policy_arn" {
  description = "ARN of the Terraform State Plan-Only policy (read dev + prod)"
  value       = aws_iam_policy.terraform_state_plan_only.arn
}

output "security_boundary_policy_arn" {
  description = "ARN of the Security Boundary policy"
  value       = aws_iam_policy.security_boundary_dev.arn
}

# =============================================================================
# User Outputs
# =============================================================================
output "plan_cross_user_name" {
  description = "Name of the plan-cross IAM user"
  value       = aws_iam_user.plan_cross.name
}

output "plan_cross_user_arn" {
  description = "ARN of the plan-cross IAM user"
  value       = aws_iam_user.plan_cross.arn
}

# =============================================================================
# Role Outputs
# =============================================================================
output "infrastructure_role_arn" {
  description = "ARN of the GitHub Actions Infrastructure role"
  value       = aws_iam_role.github_actions_infrastructure.arn
}

output "infrastructure_role_name" {
  description = "Name of the GitHub Actions Infrastructure role"
  value       = aws_iam_role.github_actions_infrastructure.name
}
