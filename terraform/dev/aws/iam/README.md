# AWS IAM Module

Provisions IAM roles, policies, and instance profiles for GitHub Actions CI/CD and EC2 instances.

## Resources Created

| Resource | Name Pattern | Description |
|----------|--------------|-------------|
| `aws_iam_role` | `GitHubActions-Infrastructure-{env}` | GitHub Actions deployment role |
| `aws_iam_role` | `wireguard-ssm-role-{env}` | EC2 role for SSM Session Manager |
| `aws_iam_instance_profile` | `wireguard-ssm-profile-{env}` | Instance profile for WireGuard EC2 |
| `aws_iam_policy` | `TerraformState-{env}` | S3/DynamoDB state access |
| `aws_iam_policy` | `SecurityBoundary-{env}` | Deny IAM/CloudTrail/Billing |

## Architecture

```
GitHub Actions
      │
      ▼
GitHubActions-Infrastructure-{env}
      │
      ├── PowerUserAccess (AWS managed)
      ├── TerraformState-{env} (custom)
      └── SecurityBoundary-{env} (custom - DENY policy)
            │
            └── Permissions Boundary: TerraformPermissionsBoundary
```

## Policies

### TerraformState-{env}
- S3: ListBucket, GetObject, PutObject, DeleteObject on `{bucket}/{env}/*`
- DynamoDB: GetItem, PutItem, DeleteItem for state locking

### SecurityBoundary-{env}
**DENY** policy that blocks:
- IAM mutation (create/delete/attach roles, policies, users)
- CloudTrail modifications
- Billing/Cost Management access
- PassRole except for allowed EC2 roles

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `environment` | Environment name | `dev` |
| `account_id` | AWS Account ID | *sensitive* |
| `github_repo` | GitHub repo (owner/repo) | `mohamedsabry-dev/hybrid-cloud-infrastructure` |
| `state_bucket_name` | S3 bucket for TF state | - |
| `lock_table_name` | DynamoDB lock table | - |
| `region` | AWS region | `us-east-1` |

## Outputs

| Output | Description |
|--------|-------------|
| `terraform_state_policy_arn` | ARN of TerraformState policy |
| `security_boundary_policy_arn` | ARN of SecurityBoundary policy |
| `infrastructure_role_arn` | ARN of GitHub Actions role |
| `infrastructure_role_name` | Name of GitHub Actions role |
| `wireguard_instance_profile_name` | Instance profile for EC2 |

## OIDC Trust

GitHub Actions role trusts:
- Provider: `token.actions.githubusercontent.com`
- Condition: `repo:{github_repo}:ref:refs/heads/{environment}`

Only workflows running on the matching branch can assume the role.

## Usage

```bash
cd terraform/dev/aws/iam
terraform init
terraform plan -var="account_id=123456789012"
terraform apply -var="account_id=123456789012"
```

## Security Notes

- Infrastructure role has PowerUserAccess but is constrained by SecurityBoundary
- Cannot create/modify IAM resources (prevents privilege escalation)
- Cannot disable CloudTrail (audit protection)
- PassRole limited to specific EC2 roles only

## Post-IAM Workflow: Run Compute Workflow

**IMPORTANT:** After IAM workflow completes, run the Compute workflow.

The compute module references the instance profile via remote state:
```hcl
iam_instance_profile = data.terraform_remote_state.iam.outputs.wireguard_instance_profile_name
```

If IAM resources are recreated (e.g., naming change), the EC2 loses its instance profile until compute workflow runs and reattaches it.

## State Migration History

### 2026-03-21: Consolidation - Prefix to Suffix Naming

Changed Terraform resource block names for consistency between dev/prod:

```bash
# Executed via workflow, then removed from workflow
terraform state mv aws_iam_role.dev_wireguard_ssm aws_iam_role.wireguard_ssm
terraform state mv aws_iam_role_policy_attachment.dev_wireguard_ssm_core aws_iam_role_policy_attachment.wireguard_ssm_core
terraform state mv aws_iam_instance_profile.dev_wireguard_ssm aws_iam_instance_profile.wireguard_ssm
terraform state mv aws_iam_policy.terraform_state_dev aws_iam_policy.terraform_state
terraform state mv aws_iam_policy.security_boundary_dev aws_iam_policy.security_boundary
```

This also triggered AWS resource name changes (forces replacement):
- `dev-wireguard-ssm-role` → `wireguard-ssm-role-dev`
- `dev-wireguard-ssm-profile` → `wireguard-ssm-profile-dev`
- `SecurityBoundary-Dev` → `SecurityBoundary-dev`
- `TerraformState-Dev` → `TerraformState-dev`
