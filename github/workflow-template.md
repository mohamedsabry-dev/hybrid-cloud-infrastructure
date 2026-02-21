# Workflow Template Blocks

Reusable blocks for building GitHub Actions workflows.

---

## Block 1: Trigger Configuration

```yaml
name: "{ENV} - {Resource Name}"

on:
  push:
    branches:
      - {env}
    paths:
      - 'terraform/{env}/proxmox/{path}/**'
      - '.github/workflows/{workflow-file}.yml'

  workflow_dispatch:

permissions:
  id-token: write   # Required for OIDC authentication with AWS
  contents: read    # Required for actions/checkout

env:
  ENVIRONMENT: {env}
  TF_WORKING_DIR: terraform/{env}/proxmox/{path}
```

---

## Block 2: Trigger Lock (Safe Execution)

```yaml
jobs:
  deploy:
    name: "Deploy {Resource}"
    runs-on: macOS
    # Skip if locked (unless manual trigger)
    if: ${{ github.event_name == 'workflow_dispatch' || vars.{RESOURCE}_{ENV}_LOCKED != 'true' }}

    defaults:
      run:
        working-directory: ${{ env.TF_WORKING_DIR }}
```

> **Note:** Create lock variable in GitHub Settings → Variables → `{RESOURCE}_{ENV}_LOCKED`

---

## Block 3: AWS OIDC Authentication

```yaml
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ vars.AWS_ACCOUNT_ID_{ENV} }}:role/GitHubActions-Infrastructure-${{ env.ENVIRONMENT }}
          aws-region: ${{ vars.AWS_REGION }}
```

**Dependencies:**
- IAM Role: `GitHubActions-Infrastructure-{env}`
- OIDC Provider configured in AWS
- GitHub Variables: `AWS_ACCOUNT_ID_{ENV}`, `AWS_REGION`

---

## Block 4: Fetch Secrets from AWS

```yaml
      - name: Fetch Proxmox Secrets
        run: |
          API_SECRET=$(aws secretsmanager get-secret-value \
            --secret-id {env}/proxmox/terraform-token \
            --query SecretString --output text)

          SSH_SECRET=$(aws secretsmanager get-secret-value \
            --secret-id {env}/proxmox/ssh-admin-password \
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
```

**Dependencies:**
- AWS Secrets Manager secrets:
  - `{env}/proxmox/terraform-token` → JSON with `token_id` and `token_secret`
  - `{env}/proxmox/ssh-admin-password` → plain string
- Terraform variables in `variables.tf`:
  - `proxmox_api_token` (sensitive)
  - `proxmox_ssh_password` (sensitive)
- Tools: `jq` installed on runner

---

## Block 5: Terraform with Safety Controls

```yaml
      - name: Terraform Init
        run: terraform init

      - name: Terraform Plan
        timeout-minutes: 10
        run: terraform plan -out=tfplan

      - name: Lock Cleanup Instructions
        if: failure() || cancelled()
        run: |
          echo "=============================================="
          echo "⚠️  Workflow cancelled or timed out"
          echo "=============================================="
          echo ""
          echo "State may be locked. To release:"
          echo ""
          echo "AWS Console → DynamoDB → Tables"
          echo "→ hybrid-cloud-infrastructure-tf-state-lock-{env}"
          echo "→ Explore items >> Find the Locked ID"
          echo "→ Delete item"
          echo ""
          echo "=============================================="

      - name: Review Window
        run: |
          echo "⏳ 3-minute review window started at $(date)"
          echo "Environment: ${{ env.ENVIRONMENT }}"
          echo "Plan output is available above for auditor review"
          sleep 180
          echo "✅ Review window ended at $(date)"

      - name: Terraform Apply
        run: terraform apply -auto-approve tfplan
```

**Safety Features:**
- `timeout-minutes: 10` → Prevents hung workflows
- `Lock Cleanup Instructions` → Shows on failure/cancel
- `Review Window` → 3-minute pause after plan for manual review

---

## Placeholders Reference

| Placeholder | Example | Description |
|-------------|---------|-------------|
| `{ENV}` | `DEV` | Uppercase for variables |
| `{env}` | `dev` | Lowercase for paths/branches |
| `{Resource Name}` | `Proxmox Golden Image` | Display name |
| `{RESOURCE}` | `GOLDEN_IMAGE` | Lock variable prefix |
| `{path}` | `vms/golden-image` | Path under proxmox/ |
| `{workflow-file}` | `dev-golden-vm` | Workflow filename |
