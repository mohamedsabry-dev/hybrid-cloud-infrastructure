# Actions Secrets & Variables

**Location:** GitHub Repo > Settings > Secrets and variables > Actions

---

## Repository Variables

Settings → Secrets and variables → Actions → Variables

| Variable Name | Value | Purpose |
|---------------|-------|---------|
| `AWS_ACCOUNT_ID_DEV` | xxxxxxxxxxxx | DEV AWS account ID |
| `AWS_ACCOUNT_ID_PROD` | xxxxxxxxxxxx | PROD AWS account ID |
| `AWS_REGION` | eu-west-2 | Default AWS region (London) |

### Workflow Lock Variables

| Variable Name | Value | Purpose |
|---------------|-------|---------|
| `GOLDEN_IMAGE_DEV_LOCKED` | false | Lock DEV golden image workflow |
| `GOLDEN_IMAGE_PROD_LOCKED` | true | Lock PROD golden image workflow |
| `GOLDEN_LXC_DEV_LOCKED` | true | Lock DEV LXC workflow |
| `TEST_CLONES_DEV_LOCKED` | true | Lock DEV test clones workflow |
| `TEST_CLONES_PROD_LOCKED` | true | Lock PROD test clones workflow |

### Why Workflow Locks? (Safe Trigger Mechanism)

The `*_LOCKED` variables provide a safe trigger mechanism as a workaround for:

- **workflow_dispatch limitation:** Manual trigger only works on default branch (main), cannot manually trigger workflows from dev/prod branches directly
- **Environment approval gates:** Only available in GitHub Enterprise, not GitHub Pro

**How it works:**

| Lock Value | Behavior |
|------------|----------|
| `true` | Workflow skips execution (safe default) |
| `false` | Workflow runs on push |
| `workflow_dispatch` | Always runs (manual override) |

**Usage in workflow:**
```yaml
jobs:
  deploy:
    runs-on: macOS
    # Skip if locked (unless manual trigger)
    if: ${{ github.event_name == 'workflow_dispatch' || vars.GOLDEN_IMAGE_DEV_LOCKED != 'true' }}
```

**To trigger a workflow:**
1. Set variable to `false` in GitHub UI
2. Push to branch (workflow runs)
3. Set variable back to `true` (re-lock)

---

## Repository Secrets

Settings → Secrets and variables → Actions → Secrets

> **Note:** No secrets stored directly in GitHub.
> All sensitive data retrieved from AWS Secrets Manager at runtime via OIDC.

**Why:**
- Secrets Manager provides audit trail (CloudTrail)
- Centralized secret management
- Easy rotation without updating GitHub
- OIDC = no long-lived credentials stored

---

## AWS Secrets Manager

Secrets are stored in AWS Secrets Manager and fetched at runtime.

### DEV Account Secrets (xxxxxxxxxxxx)

| Secret Path | Content |
|-------------|---------|
| `dev/proxmox/terraform-token` | `{"token_id": "...", "token_secret": "..."}` |
| `dev/proxmox/ssh-admin-password` | SSH password for admin_dev user |
| `dev/proxmox/vm-root-password` | Root password for VMs (cloud-init) |
| `dev/proxmox/gandalf-password` | Break-glass emergency password |

### PROD Account Secrets (xxxxxxxxxxxx)

| Secret Path | Content |
|-------------|---------|
| `prod/proxmox/terraform-token` | `{"token_id": "...", "token_secret": "..."}` |
| `prod/proxmox/ssh-admin-password` | SSH password for admin_prod user |
| `prod/proxmox/vm-root-password` | Root password for VMs (cloud-init) |
| `prod/proxmox/gandalf-password` | Break-glass emergency password |

---

## Fetching Secrets in Workflows

**Pattern:** OIDC → Assume Role → Get Secret

```yaml
env:
  ENVIRONMENT: dev
  TF_WORKING_DIR: terraform/dev/proxmox/...

steps:
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
```

---

## How It All Works

**Flow:** OIDC → AWS → Secrets Manager → Mask → TF_VAR → Terraform → Provider

```
┌─────────────┐    ┌─────────────┐    ┌─────────────────┐    ┌─────────────┐
│  GitHub     │───▶│  AWS OIDC   │───▶│ Secrets Manager │───▶│  Workflow   │
│  Workflow   │    │  Auth       │    │  (fetch secrets)│    │  (mask)     │
└─────────────┘    └─────────────┘    └─────────────────┘    └──────┬──────┘
                                                                    │
                                                                    ▼
┌─────────────┐    ┌─────────────┐    ┌─────────────────┐    ┌─────────────┐
│  Proxmox    │◀───│  Provider   │◀───│  Terraform      │◀───│ $GITHUB_ENV │
│  Server     │    │  Block      │    │  var.*          │    │ TF_VAR_*    │
└─────────────┘    └─────────────┘    └─────────────────┘    └─────────────┘
```

### Step-by-Step

1. Workflow authenticates to AWS via OIDC (no stored credentials)
2. AWS CLI fetches secrets from Secrets Manager
3. Workflow masks secrets with `::add-mask::` (hides from logs)
4. Workflow writes `TF_VAR_*` to `$GITHUB_ENV` file
5. GitHub makes `TF_VAR_*` available as env vars for next steps
6. Terraform reads `TF_VAR_proxmox_*` → maps to `var.proxmox_*`
7. Provider block uses `var.*` to authenticate
8. Provider connects to Proxmox (API + SSH)

### TF_VAR Mapping

| Environment Variable | Terraform Variable |
|---------------------|-------------------|
| `TF_VAR_proxmox_api_token` | `var.proxmox_api_token` |
| `TF_VAR_proxmox_ssh_password` | `var.proxmox_ssh_password` |

### Required Terraform Variables (variables.tf)

```hcl
variable "proxmox_api_token" {
  type      = string
  sensitive = true      # Marked sensitive - won't show in logs/plan
}

variable "proxmox_ssh_password" {
  type      = string
  sensitive = true
}
```

### Provider Block (provider.tf)

```hcl
provider "proxmox" {
  endpoint  = var.proxmox_api_url       # https://pve-dev.lab.local:8006
  api_token = var.proxmox_api_token     # From TF_VAR_proxmox_api_token
  insecure  = var.proxmox_tls_insecure  # true (self-signed cert)

  ssh {
    username = var.proxmox_ssh_username # admin_dev
    password = var.proxmox_ssh_password # From TF_VAR_proxmox_ssh_password
  }
}
```

### Why Both API Token AND SSH?

Proxmox API has limitations - some operations require SSH:

| Operation | API | SSH | Example |
|-----------|-----|-----|---------|
| Create/manage VMs | ✅ | - | `proxmox_virtual_environment_vm` |
| Upload snippets (source_raw) | ❌ | ✅ | cloud-init configs |
| Upload files to storage | ❌ | ✅ | `proxmox_virtual_environment_file` |
| Run commands on Proxmox host | ❌ | ✅ | - |

> **Note:** This is an API limitation, not a privilege issue.
> The API endpoint for uploading raw content simply doesn't exist.

### Which Workflows Need SSH?

| Workflow | Uses cloud-init snippets? | Needs SSH? |
|----------|---------------------------|------------|
| golden-image | No (ISO install) | No |
| test-clones | Yes (source_raw) | Yes |
| golden-lxc | Yes (source_raw) | Yes |

---

## Variable Naming Convention

**Pattern:** `{RESOURCE}_{ENV}_LOCKED`

**Examples:**
- `GOLDEN_IMAGE_DEV_LOCKED`
- `GOLDEN_IMAGE_PROD_LOCKED`
- `TEST_CLONES_DEV_LOCKED`
- `INFRA_DEV_LOCKED` (future)
- `IAM_DEV_LOCKED` (future)
