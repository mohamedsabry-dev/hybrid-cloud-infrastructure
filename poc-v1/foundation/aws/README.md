# Pre-Flight Terraform Module

Bootstrap module that creates the S3 bucket and DynamoDB table for Terraform remote state management.

## Resources Created

| Resource | Purpose |
|----------|---------|
| S3 Bucket | Stores Terraform state files |
| DynamoDB Table | State locking to prevent concurrent modifications |

### S3 Bucket Features
- Versioning enabled
- AES256 server-side encryption
- Public access blocked
- Self-logging to `logs/` prefix
- Lifecycle: expire old versions after 90 days

### DynamoDB Table Features
- Provisioned capacity with auto-scaling (1-5 RCU/WCU)
- Target utilization threshold: 75%
- Point-in-time recovery enabled
- Server-side encryption enabled

## Files

| File | Description |
|------|-------------|
| `main.tf` | Provider configuration and backend settings |
| `variables.tf` | Input variable definitions |
| `s3.tf` | S3 bucket and related resources |
| `dynamodb.tf` | DynamoDB table and auto-scaling policies |
| `outputs.tf` | Output values for use by other modules |
| `dev.tfvars` | Development environment values |
| `prod.tfvars` | Production environment values |

## Usage

### Phase 1: Initial Deployment (Local State)

```bash
# Dev environment
terraform init
terraform plan -var-file="dev.tfvars"
terraform apply -var-file="dev.tfvars"

# Prod environment
terraform init
terraform plan -var-file="prod.tfvars"
terraform apply -var-file="prod.tfvars"
```

### Phase 2: Migrate to Remote State

After the S3 bucket and DynamoDB table are created:

1. Uncomment the backend block in `main.tf`
2. Run migration:
```bash
terraform init -migrate-state -force-copy
```

## GitHub Actions

The workflow is triggered by:
- Commit message containing `runtf.dev` → deploys to dev
- Commit message containing `runtf.prod` → deploys to prod
- Manual dispatch via GitHub Actions UI

## Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `aws_region` | AWS region | Yes |
| `environment` | Environment name (dev/prod) | Yes |
| `bucket_name` | S3 bucket name for state | Yes |
| `dynamodb_table_name` | DynamoDB table name for locking | Yes |
| `enable_versioning` | Enable S3 versioning | No (default: true) |
| `enable_encryption` | Enable S3 encryption | No (default: true) |

## Outputs

| Output | Description |
|--------|-------------|
| `s3_bucket_name` | Name of the created S3 bucket |
| `s3_bucket_arn` | ARN of the S3 bucket |
| `dynamodb_table_name` | Name of the DynamoDB table |
| `dynamodb_table_arn` | ARN of the DynamoDB table |
| `backend_config` | Backend configuration for other Terraform projects |
