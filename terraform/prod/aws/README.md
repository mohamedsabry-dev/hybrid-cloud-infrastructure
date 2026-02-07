# Prod - AWS

AWS infrastructure for the prod environment (Account: 969041180300).

## Modules

| Module | Description |
|--------|-------------|
| `iam/` | GitHub Actions roles and security policies |
| `secrets/` | Secrets Manager for Proxmox credentials |

## Bootstrap

`bootstrap-prod.yaml` - CloudFormation template that creates:
- GitHub OIDC Provider
- TerraformAdmin role (full admin for IAM changes)
- S3 bucket for Terraform state
- DynamoDB table for state locking
- Permissions Boundary

Deploy bootstrap first before running Terraform modules.
