# Deployment Workflow Pattern

How code flows from development to production.

---

## Standard Changes (No IAM)

**Path:** `dev` → `prod` → `main`
**Use for:** Proxmox VMs, LXCs, infrastructure changes (no IAM/security)

```
┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐
│  dev    │────▶│  Test   │────▶│  prod   │────▶│  main   │
│ (push)  │     │  Pass   │     │  (PR)   │     │  (PR)   │
└─────────┘     └─────────┘     └─────────┘     └─────────┘
     │                              │               │
     ▼                              ▼               ▼
Infrastructure-dev            Infrastructure-prod   Milestone
workflow runs                 workflow runs         complete
```

### Steps

1. Push changes to `dev` branch
2. Infrastructure-dev workflow runs automatically
3. Test and verify in DEV environment
4. Create PR from `dev` → `prod` (requires review & approval)
5. Merge PR → Infrastructure-prod workflow runs
6. Test and verify in PROD environment
7. When phase/milestone complete: PR from `prod` → `main`

---

## IAM/Security Changes

**Path:** `dev` → `dev-security` → `prod-security` → `prod` → `main`
**Use for:** IAM roles, policies, permissions, security configurations

```
┌─────────┐     ┌──────────────┐     ┌───────────────┐     ┌─────────┐
│  dev    │────▶│ dev-security │────▶│ prod-security │────▶│  prod   │
│ (push)  │     │    (PR)      │     │     (PR)      │     │  (PR)   │
└─────────┘     └──────────────┘     └───────────────┘     └─────────┘
                      │                    │                    │
                      ▼                    ▼                    ▼
                TerraformAdmin-dev   TerraformAdmin-prod   Infrastructure-prod
                workflow runs        workflow runs         workflow runs
```

### Steps

1. Push changes to `dev` branch (test infrastructure first)
2. Create PR from `dev` → `dev-security` (requires review)
3. Merge PR → TerraformAdmin-dev workflow runs (IAM changes in DEV AWS)
4. Test and verify IAM/security in DEV environment
5. Create PR from `dev-security` → `prod-security` (requires review)
6. Merge PR → TerraformAdmin-prod workflow runs (IAM changes in PROD AWS)
7. Create PR from `prod-security` → `prod` (infrastructure deployment if needed)
8. When phase/milestone complete: PR from `prod` → `main`

---

## Path Summary

| Change Type | Branch Path |
|-------------|-------------|
| Infrastructure | `dev` → `prod` → `main` |
| IAM/Security | `dev` → `dev-security` → `prod-security` → `prod` → `main` |

---

## PR Requirements

| Target Branch | Review Required | CI Checks |
|---------------|-----------------|-----------|
| `main` | Yes (1+) | Required |
| `prod` | Yes (1+) | Required |
| `prod-security` | Yes (1+) | Required |
| `dev-security` | Yes (1+) | - |
| `dev` | No | - |
---

## Sample Workflow Structure

```yaml
name: Dev - Infrastructure

on:
  push:
    branches: [dev]
    paths:
      - 'terraform/dev/proxmox/**'
      - '.github/workflows/dev-infrastructure.yml'
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

env:
  ENVIRONMENT: dev
  TF_WORKING_DIR: terraform/dev/proxmox

jobs:
  deploy:
    runs-on: macOS
    if: ${{ github.event_name == 'workflow_dispatch' || vars.INFRA_DEV_LOCKED != 'true' }}

    defaults:
      run:
        working-directory: ${{ env.TF_WORKING_DIR }}

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ vars.AWS_ACCOUNT_ID_DEV }}:role/GitHubActions-Infrastructure-${{ env.ENVIRONMENT }}
          aws-region: ${{ vars.AWS_REGION }}

      - name: Fetch Proxmox Secrets
        run: |
          API_SECRET=$(aws secretsmanager get-secret-value \
            --secret-id dev/proxmox/terraform-token \
            --query SecretString --output text)

          SSH_SECRET=$(aws secretsmanager get-secret-value \
            --secret-id dev/proxmox/ssh-admin-password \
            --query SecretString --output text)

          TOKEN_ID=$(echo "$API_SECRET" | jq -r '.token_id')
          TOKEN_SECRET=$(echo "$API_SECRET" | jq -r '.token_secret')

          # Mask BEFORE any use
          echo "::add-mask::${TOKEN_SECRET}"
          echo "::add-mask::${SSH_SECRET}"
          echo "::add-mask::${TOKEN_ID}=${TOKEN_SECRET}"

          # Set as TF_VAR for Terraform variables
          echo "TF_VAR_proxmox_api_token=${TOKEN_ID}=${TOKEN_SECRET}" >> $GITHUB_ENV
          echo "TF_VAR_proxmox_ssh_password=${SSH_SECRET}" >> $GITHUB_ENV

      - name: Terraform Init
        run: terraform init

      - name: Terraform Apply
        run: terraform apply -auto-approve
```
