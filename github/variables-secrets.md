# Actions Secrets & Variables

**Location:** GitHub Repo > Settings > Secrets and variables > Actions

---

## Repository Variables

Settings → Secrets and variables → Actions → Variables

| Variable Name | Value | Purpose |
|---------------|-------|---------|
| `AWS_REGION_DEV` | us-east-1 | DEV AWS region |
| `AWS_REGION_PROD` | eu-west-2 | PROD AWS region (London) |

### Workflow Lock Variables

**Pattern:** `{ENV}_INFRA_{NAME}_LOCK`

| Variable Name | Value | Purpose |
|---------------|-------|---------|
| `DEV_INFRA_GOLDEN_VM_LOCK` | true | Lock DEV golden VM workflow |
| `DEV_INFRA_GOLDEN_LXC_LOCK` | true | Lock DEV golden LXC workflow |
| `DEV_INFRA_FREEIPA_LOCK` | true | Lock DEV FreeIPA workflow |
| `DEV_INFRA_ANSIBLE_LOCK` | true | Lock DEV Ansible workflow |
| `DEV_INFRA_K8S_MASTERS_LOCK` | true | Lock DEV K8s masters workflow |
| `DEV_INFRA_K8S_WORKERS_LOCK` | true | Lock DEV K8s workers workflow |
| `PROD_INFRA_GOLDEN_VM_LOCK` | true | Lock PROD golden VM workflow |
| `PROD_INFRA_GOLDEN_LXC_LOCK` | true | Lock PROD golden LXC workflow |
| `PROD_INFRA_FREEIPA_LOCK` | true | Lock PROD FreeIPA workflow |
| `PROD_INFRA_ANSIBLE_LOCK` | true | Lock PROD Ansible workflow |

### GitHub Runner Variables

| Variable Name | Value | Purpose |
|---------------|-------|---------|
| `DEV_GH_RUNNER_NAME` | dev-local-runner | Runner name for config.sh |
| `DEV_GH_RUNNER_LABELS` | dev-local-runner | Runner labels |
| `PROD_GH_RUNNER_NAME` | prod-local-runner | Runner name for config.sh |
| `PROD_GH_RUNNER_LABELS` | prod-local-runner | Runner labels |

### Why Workflow Locks? (Safe Trigger Mechanism)

The `*_LOCK` variables provide a safe trigger mechanism as a workaround for:

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
    runs-on: mac-mini
    # Skip if locked
    if: ${{ vars.DEV_INFRA_FREEIPA_LOCK != 'true' }}
```

**To trigger a workflow:**
1. Set variable to `false` in GitHub UI
2. Push to branch (workflow runs)
3. Set variable back to `true` (re-lock)

### Auto-Lock Pattern (Golden Templates Only)

For golden templates (VM and LXC), workflows auto-lock after successful deployment.
These are "create once" resources that shouldn't be recreated accidentally.

**Which workflows auto-lock:**

| Workflow | Auto-lock? | Reason |
|----------|------------|--------|
| golden-vm | Yes | Template, create once |
| golden-lxc | Yes | Template, create once |
| freeipa | No | May need updates |
| ansible | No | May need updates |
| iam | No | May need policy changes |
| secrets | No | May add new secrets |

**Implementation:**

1. Add permission:
```yaml
permissions:
  id-token: write
  contents: read
  actions: write      # Required for gh variable set
```

2. Add step after Terraform Apply:
```yaml
- name: Lock after success
  if: success()
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  run: |
    gh variable set DEV_INFRA_GOLDEN_VM_LOCK --body "true"
```

**Why auto-lock golden templates:**
- One-time creation (template used many times)
- Prevents accidental recreation
- No need to manually re-lock after deployment
- Stateful workloads (FreeIPA, Ansible) keep manual control

---

## Repository Secrets

Settings → Secrets and variables → Actions → Secrets

| Secret Name | Purpose |
|-------------|---------|
| `AWS_ACCOUNT_ID_DEV` | DEV AWS account ID |
| `AWS_ACCOUNT_ID_PROD` | PROD AWS account ID |
| `GH_ADMIN_PAT` | Fine-grained PAT with admin:repo permission (for deploy keys) |
| `DEV_GH_RUNNER_TOKEN` | Fresh token from Settings > Actions > Runners (expires in ~1 hour) |
| `PROD_GH_RUNNER_TOKEN` | Fresh token for prod runner setup |
| `HOME_PUBLIC_IP` | Home public IP for AWS security group (allowed_ip) |
| `VPN_PUBLIC_KEY_DEV` | SSH public key for DEV VPN EC2 instance |
| `VPN_PUBLIC_KEY_PROD` | SSH public key for PROD VPN EC2 instance |
| `WG_VPN_EIP_DEV` | WireGuard VPN Elastic IP for DEV environment |
| `WG_VPN_EIP_PROD` | WireGuard VPN Elastic IP for PROD environment |

> **Note:** Most infrastructure secrets are retrieved from AWS Secrets Manager at runtime via OIDC.
> GitHub Secrets store: AWS account IDs, GitHub-specific tokens, VPN/network config.

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
      role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID_DEV }}:role/GitHubActions-Infrastructure-${{ env.ENVIRONMENT }}
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
| golden-vm | No (ISO install) | No |
| golden-lxc | No (native init) | No |
| freeipa | No (API initialization) | No |
| ansible | No (API initialization) | No |

> **Note:** SSH only needed if using `source_raw` for custom cloud-init scripts.
> Basic initialization (IP, hostname, SSH keys) works via API.

---

## Variable Naming Convention

**Lock Pattern:** `{ENV}_INFRA_{NAME}_LOCK`

**Examples:**
- `DEV_INFRA_GOLDEN_VM_LOCK`
- `DEV_INFRA_GOLDEN_LXC_LOCK`
- `DEV_INFRA_FREEIPA_LOCK`
- `DEV_INFRA_ANSIBLE_LOCK`
- `DEV_INFRA_K8S_MASTERS_LOCK`
- `DEV_INFRA_K8S_WORKERS_LOCK`
- `PROD_INFRA_FREEIPA_LOCK`

**Runner Variables Pattern:** `{ENV}_GH_RUNNER_{FIELD}`

**Examples:**
- `DEV_GH_RUNNER_NAME`
- `DEV_GH_RUNNER_LABELS`
- `PROD_GH_RUNNER_NAME`
