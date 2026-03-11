# Outputs for policy and role ARNs

# =============================================================================
# Policy ARNs
# =============================================================================
output "terraform_state_policy_arn" {
  description = "ARN of the Terraform State policy (read/write prod)"
  value       = aws_iam_policy.terraform_state_prod.arn
}

output "security_boundary_policy_arn" {
  description = "ARN of the Security Boundary policy"
  value       = aws_iam_policy.security_boundary_prod.arn
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

# =============================================================================
# WireGuard SSM Outputs
# =============================================================================
output "wireguard_instance_profile_name" {
  description = "Instance profile name for WireGuard EC2 SSM access"
  value       = aws_iam_instance_profile.prod_wireguard_ssm.name
}
