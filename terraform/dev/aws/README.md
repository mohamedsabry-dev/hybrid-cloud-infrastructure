# Dev - AWS

AWS infrastructure for the dev environment (Account: REDACTED_AWS_DEV).

## Modules

| Module | Description |
|--------|-------------|
| `iam/` | GitHub Actions roles and security policies |
| `secrets/` | Secrets Manager for Proxmox credentials |

## Bootstrap

`bootstrap-dev.yaml` - CloudFormation template that creates:
- GitHub OIDC Provider
- TerraformAdmin role (full admin for IAM changes)
- S3 bucket for Terraform state
- DynamoDB table for state locking
- Permissions Boundary

Deploy bootstrap first before running Terraform modules.
