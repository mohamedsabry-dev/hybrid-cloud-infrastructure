# Actions Secrets & Variables

**Location:** GitHub Repo > Settings > Secrets and variables > Actions

---

## Repository Secrets

| Secret Name | Purpose |
|-------------|---------|
| `AWS_ACCOUNT_ID_DEV` | DEV AWS account ID |
| `AWS_ACCOUNT_ID_PROD` | PROD AWS account ID |
| `GH_ADMIN_PAT` | Fine-grained PAT for deploy keys |
| `DEV_GH_RUNNER_TOKEN` | DEV runner token (expires ~1 hour) |
| `PROD_GH_RUNNER_TOKEN` | PROD runner token (expires ~1 hour) |
| `HOME_PUBLIC_IP` | Home IP for AWS security group |
| `VPN_PUBLIC_KEY_DEV` | DEV VPN EC2 SSH key |
| `VPN_PUBLIC_KEY_PROD` | PROD VPN EC2 SSH key |

---

## Repository Variables

| Variable Name | Value | Purpose |
|---------------|-------|---------|
| `AWS_REGION_DEV` | us-east-1 | DEV AWS region |
| `AWS_REGION_PROD` | eu-west-2 | PROD AWS region |
| `DEV_GH_RUNNER_NAME` | dev-local-runner | Runner name |
| `DEV_GH_RUNNER_LABELS` | dev-local-runner | Runner labels |
| `PROD_GH_RUNNER_NAME` | prod-local-runner | Runner name |
| `PROD_GH_RUNNER_LABELS` | prod-local-runner | Runner labels |

---

## Workflow Lock Variables

**Pattern:** `{ENV}_INFRA_{NAME}_LOCK` or `{ENV}_SVC_{NAME}`

| Lock Value | Behavior |
|------------|----------|
| `true` | Job skips |
| `false` or unset | Job runs |

### DEV Locks

| Variable | Job |
|----------|-----|
| `DEV_INFRA_GOLDEN_VM_LOCK` | Golden VM |
| `DEV_INFRA_GOLDEN_LXC_LOCK` | Golden LXC |
| `DEV_INFRA_FREEIPA_LOCK` | FreeIPA VM |
| `DEV_INFRA_ANSIBLE_LOCK` | Ansible LXC |
| `DEV_INFRA_LOCAL_RUNNER_LOCK` | Local runner LXC |
| `DEV_INFRA_NGINX_LOCK` | Nginx LXC |
| `DEV_INFRA_VAULT_CLUSTER_LOCK` | Vault cluster |
| `DEV_INFRA_K8S_MASTERS_LOCK` | K8s masters |
| `DEV_INFRA_K8S_WORKERS_LOCK` | K8s workers |
| `DEV_PROXMOX_STORAGE_NAS_CONFIG` | Proxmox storage |
| `DEV_SVC_DEPLOY_KEY_LOCK` | Deploy key setup |
| `DEV_SVC_ANSIBLE_SETUP_LOCK` | Ansible setup |
| `DEV_SVC_GH_RUNNER_LOCK` | GitHub runner setup |
| `DEV_SVC_LOCAL_RUNNER_TOOLS_LOCK` | Runner tools install |
| `DEV_SVC_VAULT_SETUP` | Vault service |
| `DEV_SVC_FREEIPA_SETUP` | FreeIPA service |

### PROD Locks

| Variable | Job |
|----------|-----|
| `PROD_INFRA_GOLDEN_VM_LOCK` | Golden VM |
| `PROD_INFRA_GOLDEN_LXC_LOCK` | Golden LXC |
| `PROD_INFRA_FREEIPA_LOCK` | FreeIPA VM |
| `PROD_INFRA_ANSIBLE_LOCK` | Ansible LXC |
| `PROD_INFRA_LOCAL_RUNNER_LOCK` | Local runner LXC |
| `PROD_INFRA_NGINX_LOCK` | Nginx LXC |
| `PROD_INFRA_VAULT_CLUSTER_LOCK` | Vault cluster |
| `PROD_INFRA_K8S_MASTERS_LOCK` | K8s masters |
| `PROD_INFRA_K8S_WORKERS_LOCK` | K8s workers |
| `PROD_PROXMOX_STORAGE_NAS_CONFIG` | Proxmox storage |
| `PROD_SVC_DEPLOY_KEY_LOCK` | Deploy key setup |
| `PROD_SVC_ANSIBLE_SETUP_LOCK` | Ansible setup |
| `PROD_SVC_GH_RUNNER_LOCK` | GitHub runner setup |
| `PROD_SVC_LOCAL_RUNNER_TOOLS_LOCK` | Runner tools install |
| `PROD_SVC_VAULT_SETUP` | Vault service |
| `PROD_SVC_FREEIPA_SETUP` | FreeIPA service |

---

## AWS Secrets Manager

Secrets fetched at runtime via OIDC (no stored credentials).

### DEV Account

| Secret Path | Content |
|-------------|---------|
| `dev/proxmox/terraform-token` | `{"token_id": "...", "token_secret": "..."}` |
| `dev/golden-image/lxc-root-password` | LXC root password |
| `dev/ansible/ssh-public-key` | Ansible SSH public key |
| `dev/ansible/vault-password` | Ansible Vault password |
| `dev/local-runner/ssh-public-key` | Local runner SSH key |
| `dev/vault/unseal-credentials` | `{"access_key_id": "...", "secret_access_key": "..."}` |

### PROD Account

| Secret Path | Content |
|-------------|---------|
| `prod/proxmox/terraform-token` | `{"token_id": "...", "token_secret": "..."}` |
| `prod/golden-image/lxc-root-password` | LXC root password |
| `prod/ansible/ssh-public-key` | Ansible SSH public key |
| `prod/ansible/vault-password` | Ansible Vault password |
| `prod/local-runner/ssh-public-key` | Local runner SSH key |
| `prod/vault/unseal-credentials` | `{"access_key_id": "...", "secret_access_key": "..."}` |

---

## Related Documentation

| Topic | Document |
|-------|----------|
| Workflow patterns | `.github/workflows/workflow-guide.txt` |
| Secret fetching examples | `.github/workflows/README.md` |
| Deployment flow | `github/deployment-pattern.md` |
