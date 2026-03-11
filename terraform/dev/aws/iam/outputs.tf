# Outputs for policy and role ARNs

# =============================================================================
# Policy ARNs
# =============================================================================
output "terraform_state_policy_arn" {
  description = "ARN of the Terraform State policy (read/write dev)"
  value       = aws_iam_policy.terraform_state_dev.arn
}

output "security_boundary_policy_arn" {
  description = "ARN of the Security Boundary policy"
  value       = aws_iam_policy.security_boundary_dev.arn
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

output "wireguard_instance_profile_name" {
    value = aws_iam_instance_profile.dev_wireguard_ssm.name
}