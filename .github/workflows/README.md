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
| `{env}-k8s-full-setup` | 3 | Deploy K8s Masters + Workers + Cluster Setup |
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
| `{env}-aws-vault-trust` | dev-security/prod-security | Deploy IAM user/role for Vault AWS Secrets Engine |

### Container Images

| Workflow | Branch | Purpose |
|----------|--------|---------|
| `build-docker-images` | dev | Build & push custom container images to GHCR (remediation, etcd-backup) |

Triggered by changes under `kubernetes/docker-images/**`. Uses `dorny/paths-filter` to rebuild only the image whose source changed. Images are pushed to `ghcr.io/<owner>/<image>:latest` and consumed by the Kubernetes workloads (self-healing remediation pod, etcd backup CronJob).

---

## Patterns worth knowing

- **`terraform init -upgrade` everywhere.** Picks up the latest patch version within each pinned constraint. Providers are cached in the Mac Mini runner's `~/.terraform.d/providers-mirror`, so no download overhead. Pin exact versions only when debugging a regression.

- **Mask secrets BEFORE jq parsing.** `echo "::add-mask::${API_SECRET}"` runs on the raw JSON first, then individual field extraction happens after. Otherwise a jq error could leak the secret into logs.

- **`ANSIBLE_HOST` / `ANSIBLE_USER` env vars at workflow top.** Not hardcoded in every step. Single source per workflow, dev/prod difference is one line.

- **`always()` on dependent jobs**, so each evaluates its own lock instead of being auto-skipped when upstream is skipped:
  ```
  if: ${{ always() && needs.deploy.result != 'failure' && needs.deploy.result != 'cancelled' && vars.LOCK != 'true' }}
  ```
  Rows in a multi-job workflow: success/skipped upstream → downstream runs (if unlocked); failed/cancelled upstream → downstream skips.

- **Three-tier comment separators** (file / section / job) for scannability. See any existing workflow for the exact format.

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

The bpg/proxmox provider's `clone` block silently ignores `user_account` keys/passwords on LXCs. All LXC modules in this repo use the `operating_system { template_file_id = ... }` pattern (vzdump template file on `nas-iso`) instead. Full reasoning + commands:

- [`../../terraform/dev/proxmox/lxc/DESIGN.md`](../../terraform/dev/proxmox/lxc/DESIGN.md) — why template-file vs clone-from-ID
- [`../../proxmox/golden_templates/lxc-template-finalize-guide.txt`](../../proxmox/golden_templates/lxc-template-finalize-guide.txt) — the vzdump + move commands

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
