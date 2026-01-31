# Bootstrap CloudFormation

Phase 0 foundation infrastructure for hybrid cloud setup.

## Folder Structure

| File | Purpose |
|------|---------|
| `bootstrap.yaml` | Main CloudFormation template |
| `deployment-file.yaml` | Deployment configuration for CI/CD |

## What Gets Created

### 1. GitHub OIDC Provider
- Enables GitHub Actions to authenticate with AWS using OpenID Connect
- Eliminates need for long-lived AWS credentials in GitHub

### 2. Terraform State Backend
- **S3 Bucket**: `hybrid-cloud-infrastructure-terraform-state`
  - Versioning enabled
  - AES256 encryption
  - Public access blocked
- **DynamoDB Table**: `hybrid-cloud-infrastructure-terraform-state-lock`
  - Prevents concurrent Terraform runs

### 3. Audit Logs Bucket
- **S3 Bucket**: `hybrid-cloud-infrastructure-audit-logs`
  - 365-day retention policy
  - Versioning enabled
  - Encrypted at rest

## AWS Detection

The stack is detected via CloudFormation with:
- **Stack Name**: Defined during deployment
- **Tags**: `Phase: Bootstrap`, `ManagedBy: CloudFormation`
- **Exports**: Resources are exported for cross-stack references

## Deployment

Triggered via CI/CD using the `deployment-file.yaml` configuration which points to the template and applies consistent tagging.
