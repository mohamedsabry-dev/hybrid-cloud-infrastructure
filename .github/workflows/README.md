# Workflow Conventions

Patterns and conventions used across all workflow YAML files in this directory.
For architecture, branch strategy, runners, and secrets — see [`../../github/`](../../github/).

---

## Quick Reference

| Environment | Branch | Ansible Host | Runner Host |
|-------------|--------|--------------|-------------|
| DEV | dev | 10.0.63.10 | 10.0.63.20 |
| PROD | prod | 10.0.53.10 | 10.0.53.20 |

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
| `build-docker-remediation` | dev | Build & push remediation image to GHCR |
| `build-docker-etcd-backup` | dev | Build & push etcd-backup image to GHCR |

Each triggers only on changes under its own `kubernetes/docker-images/{name}/**` path.

---

## Patterns

- **`terraform init -upgrade` everywhere.** Picks up the latest patch within each pinned constraint. Providers cached in the Mac Mini's `~/.terraform.d/providers-mirror`.

- **Mask secrets BEFORE jq parsing.** `echo "::add-mask::${API_SECRET}"` runs on the raw JSON first, then individual field extraction happens after.

- **`ANSIBLE_HOST` / `ANSIBLE_USER` env vars at workflow top.** Single source per workflow, dev/prod difference is one line.

- **`always()` on dependent jobs**, so each evaluates its own lock instead of being auto-skipped when upstream is skipped:
  ```
  if: ${{ always() && needs.deploy.result != 'failure' && needs.deploy.result != 'cancelled' && vars.LOCK != 'true' }}
  ```

- **Three-tier comment separators** (file / section / job) for scannability. See any existing workflow for the format.

---

## Lock Variables

| Type | Variable Pattern | Example |
|------|------------------|---------|
| Infrastructure | `{ENV}_INFRA_{NAME}_LOCK` | `DEV_INFRA_ANSIBLE_LOCK` |
| Service | `{ENV}_SVC_{NAME}_LOCK` | `DEV_SVC_VAULT_SETUP` |

| Lock Value | Behavior |
|------------|----------|
| `true` | Job skips |
| `false` or unset | Job runs |
| `workflow_dispatch` | Always runs (manual override) |

Full lock list: [`../../github/variables-secrets.md`](../../github/variables-secrets.md)

---

## Writing New Workflows

See **[workflow-guide.txt](workflow-guide.txt)** for the full template, checklists, and common mistakes.
