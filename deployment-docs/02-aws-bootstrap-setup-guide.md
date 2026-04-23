# AWS Bootstrap & IAM - Initial Setup Guide

Note: If you face issues during deployment, check the troubleshooting/ folder
for the related technology section. Most common issues have been documented there.
Relevant folders: troubleshooting/aws/, troubleshooting/github-actions/

---

## Overview

This guide covers the ONE-TIME bootstrap of AWS infrastructure that enables all
subsequent Terraform automation via GitHub Actions. This includes OIDC federation,
Terraform state storage, and a 2-tier IAM role architecture.

IMPORTANT: This is the VERY FIRST AWS setup step. Deploy bootstrap stack BEFORE
creating any secrets or running any workflows.

For more details, see: aws/bootstrap.md and aws/README.md

---

### A note for anyone implementing this

The specific regions, account IDs, bucket names (with the `-v2` suffix on dev),
and admin user names shown throughout this guide are MINE. They reflect the
accounts, regions, and history I happened to land on. You do not need to
replicate any of those specifics. Pick whatever regions make sense for your
situation (cost, latency, free tier, compliance) and whatever bucket / table
names are unique to your accounts.

### Important — the mixed-region drift in my prod is NOT the design

You will see elsewhere in the repo that my prod ended up with a mixed-region
setup: prod bootstrap + most Terraform-managed resources live in `eu-west-2`,
but prod's network + compute (VPC + WireGuard EC2) live in `us-east-1`.

That is NOT a design choice, and it is NOT something you should copy. It was
forced on me by a specific WireGuard tunnel instability between my ISP and
the AWS elastic IP in `eu-west-2` (full investigation in
`/troubleshooting/network/5-wireguard-tunnel-stability-investigation.md`
— TS-NET-005). That issue is tied to my home ISP's NAT behaviour, not to
anything about the architecture.

If you are implementing this cleanly, deploy each environment as a pure
single-region mirror. The architectural intent is clean separation per
environment; the mixed-region prod in my setup is an accepted operational
drift after hitting hardware/ISP constraints, not a pattern worth following.

---

## Architecture

### Multi-Account Structure

| Environment | Account ID   | Region      | Admin User  |
|-------------|--------------|-------------|-------------|
| Development | xxxxxxxxxxxx | us-east-1   | admin_dev   |
| Production  | xxxxxxxxxxxx | eu-west-2   | admin_prod  |

Note: the regions above are the specific ones I landed on for my situation
(cost, free-tier, latency from Egypt). They are not requirements — pick
whatever regions fit your context. See "A note for anyone implementing this"
near the top of this file.

### 2-Tier IAM Role System

```
TIER 1: CloudFormation Bootstrap (Manual Deploy)
+------------------------------------------+
| GitHubActions-TerraformAdmin-{env}       |
| - Trusted Branch: {env}-security         |
| - Policy: AdministratorAccess            |
| - Constraint: PermissionsBoundary        |
| - Purpose: IAM/security changes only     |
+------------------------------------------+
              |
              | Creates via Terraform
              v
TIER 2: Terraform-Managed Roles
+------------------------------------------+
| GitHubActions-Infrastructure-{env}       |
| - Trusted Branch: {env}                  |
| - Policies: PowerUserAccess + SecurityBoundary |
| - Purpose: Infrastructure deployments    |
| - Restriction: NO IAM mutation allowed   |
+------------------------------------------+
```

Why 2-tier?
- TerraformAdmin (Tier 1): Full admin but protected by PermissionsBoundary, only for security branch
- Infrastructure (Tier 2): Day-to-day infra deployments, cannot touch IAM/CloudTrail/Billing

---

## Phase 1: Deploy Bootstrap Stack (ONE-TIME)

### 1.1 CloudFormation Templates

| Account | Template File                           | Region    | Stack Name     |
|---------|-----------------------------------------|-----------|----------------|
| Dev     | aws/deployment-stacks/bootstrap-dev.yaml | us-east-1 | bootstrap-dev  |
| Prod    | aws/deployment-stacks/bootstrap-prod.yaml | eu-west-2 | bootstrap-prod |

### 1.2 Resources Created by Bootstrap

- GitHub OIDC Provider - Identity federation for GitHub Actions
- TerraformPermissionsBoundary - Protects bootstrap resources from modification
- S3 State Bucket - Terraform state storage (versioned, encrypted)
- DynamoDB Lock Table - State locking (deletion protected)
- TerraformAdmin Role - Admin role for security branch
- Admin User - GUI admin with full admin + billing access

### 1.3 How to Deploy

IMPORTANT: Must be deployed by AWS root user (account owner email), not IAM users.

**Option 1: AWS Console (Recommended)**

1. Login to AWS Console as root user
2. Navigate to CloudFormation → Stacks → Create stack
3. Select "Upload a template file"
4. Upload bootstrap-{env}.yaml
5. Stack name: bootstrap-{env}
6. Check "I acknowledge that AWS CloudFormation might create IAM resources"
7. Create stack

**Option 2: CLI**

  # Dev (us-east-1)
  aws cloudformation deploy --template-file aws/deployment-stacks/bootstrap-dev.yaml \
      --stack-name bootstrap-dev --capabilities CAPABILITY_NAMED_IAM \
      --region us-east-1

  # Prod (eu-west-2)
  aws cloudformation deploy --template-file aws/deployment-stacks/bootstrap-prod.yaml \
      --stack-name bootstrap-prod --capabilities CAPABILITY_NAMED_IAM \
      --region eu-west-2

### 1.4 Post-Bootstrap: Enable IAM Billing Access

After stack deployment, enable billing access for admin users:

1. Sign in as root user
2. Go to: Account (top-right dropdown) → Account
3. Scroll to "IAM User and Role Access to Billing Information"
4. Click Edit → Check "Activate IAM Access" → Update

---

## Phase 2: Configure GitHub Repository

### 2.1 GitHub Secrets

Configure in: GitHub repo → Settings → Secrets and variables → Actions → Secrets

| Secret             | Value                    |
|--------------------|--------------------------|
| AWS_ACCOUNT_ID_DEV | Dev AWS Account ID       |
| AWS_ACCOUNT_ID_PROD| Prod AWS Account ID      |

### 2.2 GitHub Variables

Configure in: GitHub repo → Settings → Secrets and variables → Actions → Variables

| Variable           | Value                    |
|--------------------|--------------------------|
| AWS_REGION_DEV     | us-east-1                |
| AWS_REGION_PROD    | eu-west-2                |

---

## Phase 3: Deploy Terraform-Managed IAM Roles

### 3.1 Deploy Infrastructure Role

After bootstrap is complete, deploy the Tier 2 Infrastructure role via Terraform.

Terraform Path: terraform/dev/aws/iam/

GitHub Workflow: .github/workflows/dev-aws-iam.yml

This workflow runs on dev-security branch and uses TerraformAdmin role to create:
- GitHubActions-Infrastructure-{env} role
- TerraformState-{env} policy
- SecurityBoundary-{env} policy

### 3.2 What the IAM Terraform Creates

**GitHubActions-Infrastructure-{env} Role:**
- Trusted Branch: {env} (not {env}-security)
- Attached Policies: PowerUserAccess, TerraformState, SecurityBoundary
- PermissionsBoundary: TerraformPermissionsBoundary (from bootstrap)

**TerraformState-{env} Policy:**
- S3: ListBucket, GetObject, PutObject, DeleteObject on {env}/* path only
- DynamoDB: GetItem, PutItem, DeleteItem for state locking

**SecurityBoundary-{env} Policy:**
- Denies all IAM mutation actions
- Denies CloudTrail actions
- Denies Billing/Cost actions
- Allows PassRole only for specific EC2 roles (wireguard-ssm)

---

## Phase 4: Verify Setup

### 4.1 Verify Bootstrap Resources

  # List CloudFormation stacks
  aws cloudformation list-stacks --query "StackSummaries[?StackName=='bootstrap-dev']" --region us-east-1

  # Verify OIDC Provider
  aws iam list-open-id-connect-providers

  # Verify State Bucket
  aws s3 ls s3://hybrid-cloud-infrastructure-tf-state-dev-v2/ --region us-east-1

  # Verify Lock Table
  aws dynamodb describe-table --table-name hybrid-cloud-infrastructure-tf-state-lock-dev-v2 --region us-east-1

### 4.2 Verify IAM Roles

  # List roles
  aws iam list-roles --query "Roles[?contains(RoleName,'GitHubActions')].[RoleName,Arn]" --output table

---

## Security Features

### PermissionsBoundary Protection

The TerraformPermissionsBoundary (created by bootstrap) prevents ANY role from modifying:
- OIDC Provider
- State Bucket
- Lock Table
- TerraformAdmin Role
- PermissionsBoundary Policy itself

### State Bucket Security

- Versioning: Enabled (90-day retention for old versions)
- Encryption: AES256 server-side encryption
- Public Access: Completely blocked
- TLS: Enforced via bucket policy
- DeletionPolicy: Retain (survives stack deletion)

### DynamoDB Lock Table Security

- DeletionProtectionEnabled: true
- SSE: Server-side encryption enabled
- DeletionPolicy: Retain (survives stack deletion)

---

## Summary - File Reference

| Component                | Path                                              |
|--------------------------|---------------------------------------------------|
| Dev Bootstrap Template   | aws/deployment-stacks/bootstrap-dev.yaml          |
| Prod Bootstrap Template  | aws/deployment-stacks/bootstrap-prod.yaml         |
| Bootstrap Documentation  | aws/bootstrap.md                                  |
| AWS Quick Reference      | aws/README.md                                     |
| Dev IAM Terraform        | terraform/dev/aws/iam/                            |
| Prod IAM Terraform       | terraform/prod/aws/iam/                           |
| Dev IAM Workflow         | .github/workflows/dev-aws-iam.yml                 |
| Prod IAM Workflow        | .github/workflows/prod-aws-iam.yml                |

---

## IAM Roles Reference

### Tier 1: CloudFormation Bootstrap Roles

| Role                           | Branch         | Policies                              |
|--------------------------------|----------------|---------------------------------------|
| GitHubActions-TerraformAdmin-dev  | dev-security   | AdministratorAccess + PermissionsBoundary |
| GitHubActions-TerraformAdmin-prod | prod-security  | AdministratorAccess + PermissionsBoundary |

### Tier 2: Terraform-Managed Roles

| Role                              | Branch | Policies                                      |
|-----------------------------------|--------|-----------------------------------------------|
| GitHubActions-Infrastructure-dev  | dev    | PowerUserAccess + TerraformState + SecurityBoundary |
| GitHubActions-Infrastructure-prod | prod   | PowerUserAccess + TerraformState + SecurityBoundary |

---

## Admin Users Reference

| User        | Account | Purpose               | Policies                                        |
|-------------|---------|------------------------|------------------------------------------------|
| admin_dev   | Dev     | GUI Console Admin     | AdministratorAccess + Billing + CostOptimization |
| admin_prod  | Prod    | GUI Console Admin     | AdministratorAccess + Billing + CostOptimization |

### Local CLI Access

  # Configure profiles
  aws configure --profile dev
  aws configure --profile prod

  # Usage
  aws s3 ls --profile dev
  export AWS_PROFILE=dev && terraform init

---

## Deployment Order

0. AWS Bootstrap (this guide) - VERY FIRST
1. AWS IAM Roles (via dev-security branch)
2. AWS Secrets (see aws-secrets-setup-guide.txt)
3. Ansible + Local Runner (see ansible-runner-setup-guide.txt)
4. FreeIPA (see freeipa-initial-setup-guide.txt)
5. Vault (see vault-initial-setup-guide.txt)
6. Kubernetes (see k8s-initial-setup-guide.txt)

---
