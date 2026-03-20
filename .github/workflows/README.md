# GitHub Actions Workflows

This directory contains all CI/CD workflows for infrastructure deployment.

---

## Quick Reference

| Environment | Branch | Ansible Host | Runner Host |
|-------------|--------|--------------|-------------|
| DEV | dev | 10.0.63.10 | 10.0.63.20 |
| PROD | prod | 10.0.53.10 | 10.0.53.20 |

---

## Branch Strategy

```
Infrastructure Changes:
  dev ──────────────────────────▶ prod ──────────────────────▶ main

IAM/Security Changes:
  dev ──▶ dev-security ──▶ prod-security ──▶ prod ──▶ main
```

| Change Type | Branch Path | Reason |
|-------------|-------------|--------|
| Infrastructure | `dev` → `prod` → `main` | Standard deployment |
| IAM/Security | `dev` → `dev-security` → `prod-security` → `prod` → `main` | Extra review for security changes |

---

## Workflow Inventory

### Proxmox Infrastructure

| Workflow | Jobs | Purpose |
|----------|------|---------|
| `{env}-golden-full-setup` | 2 | Create golden VM + LXC templates |
| `{env}-ansible-full-setup` | 4 | Deploy Ansible LXC + Deploy Key + Setup |
| `{env}-freeipa-full-setup` | 2 | Deploy FreeIPA VM + Install IPA Server |
| `{env}-local-runner-full-setup` | 3 | Deploy Runner LXC + GH Runner + Tools |
| `{env}-k8s-full-setup` | 2 | Deploy K8s Masters + Workers |
| `{env}-nginx-full-setup` | 1 | Deploy Nginx reverse proxy |
| `{env}-vault-full-setup` | 2 | Deploy Vault cluster + Setup |
| `{env}-proxmox-storage` | 1 | Configure NAS storage mounts |

### AWS Infrastructure

| Workflow | Branch | Purpose |
|----------|--------|---------|
| `{env}-aws-secrets` | dev/prod | Deploy Secrets Manager secrets |
| `{env}-aws-network` | dev/prod | Deploy VPC, subnets, routing |
| `{env}-aws-compute` | dev/prod | Deploy WireGuard VPN EC2 |
| `{env}-aws-iam` | dev-security/prod-security | Deploy IAM roles & policies |
| `{env}-aws-kms-vault-unseal` | dev-security/prod-security | Deploy KMS key for Vault |

---

## Key Decisions

### 1. Always Use `terraform init -upgrade`

**Decision:** All workflows use `terraform init -upgrade`

**Why:**
- Provider versions are locked in Terraform provider blocks (e.g., `version = "~> 0.96.0"`)
- `-upgrade` gets the latest patch version within our constraints (bug fixes, security patches)
- Local provider mirror at `$HOME/.terraform.d/providers-mirror` caches versions (no overhead)
- Without `-upgrade`, Terraform reuses whatever's in `.terraform/` which may be outdated

**Exception:** If debugging a regression, temporarily pin exact version: `version = "= 0.95.0"`

### 2. Mask Secrets Immediately After Fetch

**Decision:** Mask `API_SECRET` before any jq parsing

```yaml
API_SECRET=$(aws secretsmanager get-secret-value ...)
echo "::add-mask::${API_SECRET}"    # FIRST - mask raw JSON

TOKEN_ID=$(echo "$API_SECRET" | jq -r '.token_id')
# ... then mask parsed values
```

**Why:** If jq fails or logs the input, the raw secret could be exposed. Masking first ensures it's redacted in all scenarios.

### 3. Environment Variables for IPs

**Decision:** Use `ANSIBLE_HOST`/`ANSIBLE_USER` env vars instead of hardcoded IPs

```yaml
env:
  ANSIBLE_HOST: 10.0.63.10
  ANSIBLE_USER: root

# In steps:
ssh ${{ env.ANSIBLE_USER }}@${{ env.ANSIBLE_HOST }} "command"
```

**Why:**
- Single source of truth at top of workflow
- Easy to spot environment differences (DEV=63, PROD=53)
- Prevents copy-paste errors

### 4. Multi-Job Workflow Pattern with `always()`

**Decision:** Use `always()` to ensure downstream jobs evaluate their conditions

```yaml
if: ${{ always() && needs.deploy.result != 'failure' && needs.deploy.result != 'cancelled' && vars.LOCK != 'true' }}
```

**Why:** GitHub auto-skips downstream jobs when upstream is skipped. Using `always()` forces condition evaluation so each job can decide independently based on its own lock.

| Previous Job | Next Job Behavior |
|--------------|-------------------|
| Success | Runs (if unlocked) |
| Skipped (locked) | Runs (if unlocked) |
| Failed | Skips |
| Cancelled | Skips |

### 5. Standardized Section Headers

**Decision:** Use consistent comment separators

```yaml
# =============================================================================
# FILE LEVEL - Title and description
# =============================================================================

# -----------------------------------------------------------------------------
# SECTION LEVEL - Triggers, Permissions, etc.
# -----------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # JOB LEVEL - Job description with lock variable
  # ---------------------------------------------------------------------------
```

**Why:** Makes workflows scannable, clear hierarchy, easy to navigate.

---

## Lock Variables

Workflows can be skipped using lock variables in GitHub repo settings.

### Pattern

| Type | Variable Pattern | Example |
|------|------------------|---------|
| Infrastructure | `{ENV}_INFRA_{NAME}_LOCK` | `DEV_INFRA_ANSIBLE_LOCK` |
| Service | `{ENV}_SVC_{NAME}_LOCK` | `DEV_SVC_VAULT_SETUP` |

### Usage

| Lock Value | Behavior |
|------------|----------|
| `true` | Job skips |
| `false` or unset | Job runs |
| `workflow_dispatch` | Always runs (manual override) |

---

## Terraform Import (One-Time Migration)

For adopting existing infrastructure into Terraform management:

```yaml
- name: Terraform Import
  run: |
    terraform state show <resource_address> > /dev/null 2>&1 || \
    terraform import <resource_address> <resource_id>
```

**Pattern:** `state show || import` - Only imports if not already in state (idempotent)

**When to use:**
- Migrating manually-created resources to Terraform
- Recovering from state loss
- Adopting existing infrastructure

**After use:** Remove from workflow (one-time operation)

---

## Self-Hosted Runners

### Mac Mini (Primary)

| Setting | Value |
|---------|-------|
| Label | `mac-mini` |
| Location | `~/WorkSpace/actions-runner` |
| Purpose | Terraform deployments (has AWS, Terraform, sshpass) |

### LXC Runners

| Runner | Label | Host |
|--------|-------|------|
| DEV | `dev-local-runner` | 10.0.63.20 |
| PROD | `prod-local-runner` | 10.0.53.20 |

**Purpose:** Ansible playbook execution (runs inside infrastructure network)

### Runner Token

The `{ENV}_GH_RUNNER_TOKEN` expires in ~1 hour. Generate fresh token immediately before running runner setup workflow.

---

## LXC SSH Key Injection

### The Problem

The bpg/proxmox Terraform provider's **clone method** for LXC containers does NOT support SSH key injection. Keys specified in `user_account {}` are silently ignored.

### Solution: Template Conversion

Convert LXC to template file using vzdump:

```bash
pct stop 9001
vzdump 9001 --compress gzip --storage local --mode stop
mv /var/lib/vz/dump/vzdump-lxc-9001-*.tar.gz /mnt/pve/nas-iso/template/cache/rocky-9-lxc-golden.tar.gz
```

Then use `operating_system { template_file_id }` instead of `clone {}`:

```hcl
operating_system {
  template_file_id = "nas-iso:vztmpl/rocky-9-lxc-golden.tar.gz"
  type             = "centos"
}

initialization {
  user_account {
    keys     = var.ssh_public_keys  # Works with template method
    password = var.root_password
  }
}
```

**Decision:** We use Template Conversion for all LXCs to ensure SSH keys work at first boot.

---

## Troubleshooting

### GitHub Runner Issues

| Error | Solution |
|-------|----------|
| "Invalid configuration provided for token" | Token expired. Generate fresh token. |
| "A runner exists with the same name" | Workflow uses `--replace` flag automatically. |
| Runner uses wrong name (hostname) | Use `${{ vars.VAR }}` not `${VAR}` in SSH commands. |
| "Session conflict" | Delete runner from GitHub UI first. |
| "Must run from runner root" | Run `cd /opt/actions-runner && ./svc.sh start` |

### Manual Runner Cleanup

```bash
ssh root@10.0.63.20
cd /opt/actions-runner && ./svc.sh stop && ./svc.sh uninstall
su - runner -c "cd /opt/actions-runner && ./config.sh remove --token ANY_TOKEN"
# If config.sh fails:
rm -f /opt/actions-runner/.runner /opt/actions-runner/.credentials /opt/actions-runner/.credentials_rsaparams
```

---

## Writing New Workflows

See **[workflow-guide.txt](workflow-guide.txt)** for:
- Complete file structure template
- Section header formats
- Step-by-step checklist
- Common mistakes to avoid
- Quick reference tables

---

## Related Documentation

| Document | Location | Purpose |
|----------|----------|---------|
| Deployment Pattern | `github/deployment-pattern.md` | Branch flow and PR requirements |
| Variables & Secrets | `github/variables-secrets.md` | All GitHub and AWS secrets |
| Mac Mini Runner | `github/runner-mac-mini.md` | Runner setup and tools |
| Workflow Guide | `workflows/workflow-guide.txt` | Writing new workflows |
