# Prod - IAM Module

Creates IAM roles and policies for GitHub Actions CI/CD in the prod AWS account.

## Resources

| Resource | Description |
|----------|-------------|
| `GitHubActions-Infrastructure-prod` | Role for deploying non-IAM infrastructure |
| `TerraformState-Prod` | Policy for S3 state + DynamoDB lock access |
| `SecurityBoundary-Prod` | Deny policy for IAM, CloudTrail, Billing |

## Access Control

- Role assumes via GitHub OIDC (main branch only)
- PowerUserAccess + SecurityBoundary attached
- Cannot modify IAM, CloudTrail, or billing

## Workflow

Deployed by: `.github/workflows/prod-iam.yml`
