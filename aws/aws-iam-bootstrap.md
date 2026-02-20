# AWS IAM & Bootstrap Configuration

Multi-account architecture with OIDC authentication for GitHub Actions.

---

## Account Structure

| Environment | Account ID | Admin User | Root MFA |
|-------------|------------|------------|----------|
| Production | xxxxxxxxxxxx | admin_prod | Enabled |
| Development | xxxxxxxxxxxx | admin_dev | Enabled |

---

## Bootstrap Infrastructure

### Overview

Bootstrap is a **ONE-TIME** manual deployment via AWS Console CloudFormation.
Two separate YAML files deployed as stacks - one per AWS account.

This creates the foundation (OIDC, state storage, admin role) that enables
all subsequent Terraform automation via GitHub Actions.

### CloudFormation Stacks Deployed

| Account | Stack Name | Template File | Region |
|---------|------------|---------------|--------|
| Development | dev-bootstrap | `infrastructure/aws/bootstrap-dev.yaml` | eu-west-2 |
| Production | prod-bootstrap | `infrastructure/aws/bootstrap-prod.yaml` | eu-west-2 |

**Deployment Method:** AWS Console → CloudFormation → Create Stack → Upload YAML

### Resources Created (per stack)

| Resource Type | Resource Name | Purpose |
|---------------|---------------|---------|
| `AWS::IAM::OIDCProvider` | GitHub OIDC Provider | Identity federation for GitHub Actions |
| `AWS::IAM::ManagedPolicy` | TerraformPermissionsBoundary | Protects bootstrap resources |
| `AWS::S3::Bucket` | hybrid-cloud-infrastructure-tf-state-{env} | Terraform state storage |
| `AWS::S3::BucketPolicy` | TerraformStateBucketPolicy | Enforce TLS |
| `AWS::DynamoDB::Table` | hybrid-cloud-infrastructure-tf-state-lock-{env} | State locking |
| `AWS::IAM::Role` | GitHubActions-TerraformAdmin-{env} | Admin role for security branch |

### How to Deploy (One-Time Setup)

1. Login to AWS Console with admin user (admin_dev or admin_prod)
2. Navigate to CloudFormation → Stacks → Create stack
3. Select "Upload a template file"
4. Upload bootstrap-{env}.yaml
5. Stack name: {env}-bootstrap
6. Check "I acknowledge that AWS CloudFormation might create IAM resources"
7. Create stack

**Alternative (CLI):**
```bash
aws cloudformation deploy --template-file bootstrap-{env}.yaml \
    --stack-name {env}-bootstrap --capabilities CAPABILITY_NAMED_IAM \
    --region eu-west-2
```

### Security Features

- **S3 Buckets:** Versioning, Encryption (AES256), Public Access Blocked, TLS Enforced
- **DynamoDB:** DeletionProtectionEnabled, SSE enabled
- **DeletionPolicy:** Retain on S3 and DynamoDB (survives stack deletion)
- **PermissionsBoundary:** Denies modification of OIDC, State Bucket, Lock Table, Admin Role

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

| Role | State Path Access |
|------|-------------------|
| GitHubActions-Infrastructure-dev | dev/* only |
| GitHubActions-Infrastructure-prod | prod/* only |
