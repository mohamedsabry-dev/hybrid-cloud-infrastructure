# Dev - IAM Module

Creates IAM roles and policies for GitHub Actions CI/CD in the dev AWS account.

## Resources

| Resource | Description |
|----------|-------------|
| `GitHubActions-Infrastructure-dev` | Role for deploying non-IAM infrastructure |
| `TerraformState-Dev` | Policy for S3 state + DynamoDB lock access |
| `SecurityBoundary-Dev` | Deny policy for IAM, CloudTrail, Billing |

## Access Control

- Role assumes via GitHub OIDC (dev branch only)
- PowerUserAccess + SecurityBoundary attached
- Cannot modify IAM, CloudTrail, or billing

## Workflow

Deployed by: `.github/workflows/dev-iam.yml`
