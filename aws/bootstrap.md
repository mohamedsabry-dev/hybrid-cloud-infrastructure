# AWS Bootstrap Configuration

Multi-account architecture with OIDC authentication for GitHub Actions.

> **Design notes & reasoning** — for the full iteration history behind this layout (why two accounts, why two mirrored state backends, why CloudFormation for bootstrap instead of Terraform, the 2-tier IAM origin of the `dev-security` branch, and why prod ended up in a mixed-region setup), see [`DESIGN.md`](DESIGN.md).

This file is the operational reference — account structure, resources created, how to deploy, post-bootstrap steps, IAM roles and policies, state access isolation.

---

## Account Structure

| Environment | Account ID | Region | Admin User | Root MFA |
|-------------|------------|--------|------------|----------|
| Production | xxxxxxxxxxxx | eu-west-2 (London) | admin_prod | Enabled |
| Development | xxxxxxxxxxxx | us-east-1 (N. Virginia) | admin_dev | Enabled |

> **Note:** Both envs started in `eu-west-2` (London, closest to Egypt). Dev was migrated to `us-east-1` after a Reserved Instance purchase failure. Prod's **state backend + IAM + KMS + vault-trust + secrets remain in `eu-west-2`**, but prod's **network + compute (VPC + WireGuard EC2) later moved to `us-east-1`** to escape tunnel instability with the London IP. See "Why these regions — and why prod ended up mixed" above for the full story.

---

## Bootstrap Infrastructure

### Overview

Bootstrap is a **ONE-TIME** manual deployment via AWS Console CloudFormation.
Two separate YAML files deployed as stacks - one per AWS account.

This creates the foundation (OIDC, state storage, admin role, admin user) that enables
all subsequent Terraform automation via GitHub Actions.

### CloudFormation Stacks Deployed

| Account | Stack Name | Template File | Region |
|---------|------------|---------------|--------|
| Development | bootstrap-dev | `aws/deployment-stacks/bootstrap-dev.yaml` | us-east-1 |
| Production | bootstrap-prod | `aws/deployment-stacks/bootstrap-prod.yaml` | eu-west-2 |

**Deployment Method:** AWS Console → CloudFormation → Create Stack → Upload YAML

### Resources Created (per stack)

| Resource Type | Dev Name | Prod Name | Purpose |
|---------------|----------|-----------|---------|
| `AWS::IAM::OIDCProvider` | GitHub OIDC Provider | GitHub OIDC Provider | Identity federation for GitHub Actions |
| `AWS::IAM::ManagedPolicy` | TerraformPermissionsBoundary | TerraformPermissionsBoundary | Protects bootstrap resources |
| `AWS::S3::Bucket` | hybrid-cloud-infrastructure-tf-state-dev-v2 | hybrid-cloud-infrastructure-tf-state-prod | Terraform state storage |
| `AWS::S3::BucketPolicy` | TerraformStateBucketPolicy | TerraformStateBucketPolicy | Enforce TLS |
| `AWS::DynamoDB::Table` | hybrid-cloud-infrastructure-tf-state-lock-dev-v2 | hybrid-cloud-infrastructure-tf-state-lock-prod | State locking |
| `AWS::IAM::Role` | GitHubActions-TerraformAdmin-dev | GitHubActions-TerraformAdmin-prod | Admin role for security branch |
| `AWS::IAM::User` | admin_dev | admin_prod | GUI admin with full admin + billing access |

> **Note:** Dev resources have `-v2` suffix due to migration from eu-west-2 to us-east-1.

### How to Deploy (One-Time Setup)

> **Important:** Stack must be created by the **root user** (account owner email), not IAM users.

1. Login to AWS Console as **root user**
2. Navigate to CloudFormation → Stacks → Create stack
3. Select "Upload a template file"
4. Upload bootstrap-{env}.yaml
5. Stack name: bootstrap-{env}
6. Check "I acknowledge that AWS CloudFormation might create IAM resources"
7. Create stack

**Alternative (CLI):**
```bash
# Dev (us-east-1)
aws cloudformation deploy --template-file aws/deployment-stacks/bootstrap-dev.yaml \
    --stack-name bootstrap-dev --capabilities CAPABILITY_NAMED_IAM \
    --region us-east-1

# Prod (eu-west-2)
aws cloudformation deploy --template-file aws/deployment-stacks/bootstrap-prod.yaml \
    --stack-name bootstrap-prod --capabilities CAPABILITY_NAMED_IAM \
    --region eu-west-2
```

### Post-Bootstrap: Enable IAM Billing Access

After stack deployment, enable billing access for admin users:

1. Sign in as **root user**
2. Go to: Account (top-right dropdown) → Account
3. Scroll to "IAM User and Role Access to Billing Information"
4. Click Edit → Check "Activate IAM Access" → Update

> This allows admin_dev/admin_prod to view billing dashboards and cost data.

### Security Features

- **S3 Buckets:** Versioning, Encryption (AES256), Public Access Blocked, TLS Enforced
- **DynamoDB:** DeletionProtectionEnabled, SSE enabled
- **DeletionPolicy:** Retain on S3 and DynamoDB (survives stack deletion)
- **PermissionsBoundary:** Denies modification of OIDC, State Bucket, Lock Table, Admin Role

---

## Admin Users

### Created by Bootstrap Stack

| User | Account | Policies |
|------|---------|----------|
| admin_dev | Dev | AdministratorAccess, Billing, AWSBillingReadOnlyAccess, CostOptimizationHubAdminAccess |
| admin_prod | Prod | AdministratorAccess, Billing, AWSBillingReadOnlyAccess, CostOptimizationHubAdminAccess |

### Local CLI Access

Configure named profiles for local AWS CLI access:

```bash
# Configure dev profile
aws configure --profile dev
# Access Key ID: <from admin_dev>
# Secret Access Key: <from admin_dev>
# Region: us-east-1

# Configure prod profile
aws configure --profile prod
# Access Key ID: <from admin_prod>
# Secret Access Key: <from admin_prod>
# Region: eu-west-2

# Usage
aws s3 ls --profile dev
export AWS_PROFILE=dev && terraform init
```

---

## IAM Roles

### 2-Tier Role Architecture

**TIER 1: CloudFormation Bootstrap Roles (Manual Deploy)**

| Role | Trusted Branch | Policies |
|------|----------------|----------|
| GitHubActions-TerraformAdmin-dev | dev-security | AdministratorAccess + PermissionsBoundary |
| GitHubActions-TerraformAdmin-prod | prod-security | AdministratorAccess + PermissionsBoundary |

> **Purpose:** Full admin for IAM/security changes, constrained by PermissionsBoundary

**TIER 2: Terraform-Managed Roles (Deployed by TerraformAdmin)**

| Role | Trusted Branch | Policies |
|------|----------------|----------|
| GitHubActions-Infrastructure-dev | dev | PowerUserAccess + TerraformState + SecurityBoundary |
| GitHubActions-Infrastructure-prod | prod | PowerUserAccess + TerraformState + SecurityBoundary |

> **Purpose:** Infrastructure deployments (Proxmox VMs, etc), no IAM mutation allowed

**Terraform Files:**
- `terraform/dev/aws/iam/` → Creates Infrastructure-dev role
- `terraform/prod/aws/iam/` → Creates Infrastructure-prod role

---

## IAM Policies

### CloudFormation Bootstrap Policy

| Policy Name | Purpose |
|-------------|---------|
| TerraformPermissionsBoundary | Denies modification of bootstrap resources: OIDC Provider, State Bucket, Lock Table, TerraformAdmin role, PermissionsBoundary policy itself |

### Terraform-Managed Policies

| Policy Name | Purpose |
|-------------|---------|
| TerraformState-Dev/Prod | S3 + DynamoDB access for Terraform state ({env}/* only) |
| SecurityBoundary-Dev/Prod | Denies: iam:*, cloudtrail:*, billing actions |

---

## State Access Isolation

| Role | State Bucket | State Path Access |
|------|--------------|-------------------|
| GitHubActions-Infrastructure-dev | hybrid-cloud-infrastructure-tf-state-dev-v2 | dev/* only |
| GitHubActions-Infrastructure-prod | hybrid-cloud-infrastructure-tf-state-prod | prod/* only |

---

## GitHub Repository Variables

Configure these in GitHub repo Settings → Secrets and variables → Actions → Variables:

| Variable | Dev Value | Prod Value |
|----------|-----------|------------|
| AWS_ACCOUNT_ID_DEV | xxxxxxxxxxxx | - |
| AWS_ACCOUNT_ID_PROD | - | xxxxxxxxxxxx |
| AWS_REGION_DEV | us-east-1 | - |
| AWS_REGION_PROD | - | eu-west-2 |
