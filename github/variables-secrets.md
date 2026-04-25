# Actions Secrets & Variables

**Location:** GitHub Repo > Settings > Secrets and variables > Actions

---

## Repository Secrets

| Secret Name | Purpose |
|-------------|---------|
| `AWS_ACCOUNT_ID_DEV` | DEV AWS account ID |
| `AWS_ACCOUNT_ID_PROD` | PROD AWS account ID |
| `GH_ADMIN_PAT` | Fine-grained PAT for adding deploy keys via GitHub API |
| `GH_ADMIN_PAT_FLUX` | Fine-grained PAT used by Flux CD for GitOps repo access |
| `GH_USERNAME` | GitHub username (used as Flux Git identity) |
| `DEV_GH_RUNNER_TOKEN` | DEV runner registration token (expires ~1 hour) |
| `PROD_GH_RUNNER_TOKEN` | PROD runner registration token (expires ~1 hour) |
| `HOME_PUBLIC_IP` | Home public IP for AWS security group ingress rules |
| `VPN_PUBLIC_KEY_DEV` | DEV WireGuard VPN EC2 SSH public key |
| `VPN_PUBLIC_KEY_PROD` | PROD WireGuard VPN EC2 SSH public key |

Note: `GITHUB_TOKEN` is auto-provided by GitHub Actions for operations like
GHCR login (used by `build-docker-images.yml`); it is not something you add.

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
| `DEV_SVC_K8S_CLUSTER_SETUP` | K8s cluster bootstrap (kubeadm init + Flux) |

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
| `PROD_SVC_K8S_CLUSTER_SETUP` | K8s cluster bootstrap (kubeadm init + Flux) |

---

## AWS Secrets Manager

Secrets fetched at runtime via OIDC (no stored credentials — see "Why OIDC" below).

### DEV Account

| Secret Path | Content |
|-------------|---------|
| `dev/proxmox/terraform-token` | `{"token_id": "...", "token_secret": "..."}` — Terraform auth to Proxmox API |
| `dev/golden-image/lxc-root-password` | Root password baked into golden LXC template |
| `dev/golden-image/vm-root-password` | Root password baked into golden VM template |
| `dev/ansible/ssh-public-key` | Ansible control node SSH pubkey (injected by Terraform into new nodes) |
| `dev/ansible/vault-password` | Ansible Vault file password (`~/.ansible_vault`) |
| `dev/local-runner/ssh-public-key` | Local runner SSH pubkey (copied into Ansible LXC's `authorized_keys`) |
| `dev/freeipa/admin-password` | FreeIPA `admin` user password |
| `dev/freeipa/dm-password` | FreeIPA Directory Manager (LDAP bind) password |
| `dev/super_bot/keytab` | Kerberos keytab for the `super_bot` automation user (base64) |
| `dev/vault/unseal-credentials` | `{"access_key_id": "...", "secret_access_key": "..."}` — AWS KMS auto-unseal for Vault |

### PROD Account

| Secret Path | Content |
|-------------|---------|
| `prod/proxmox/terraform-token` | `{"token_id": "...", "token_secret": "..."}` — Terraform auth to Proxmox API |
| `prod/golden-image/lxc-root-password` | Root password baked into golden LXC template |
| `prod/golden-image/vm-root-password` | Root password baked into golden VM template |
| `prod/ansible/ssh-public-key` | Ansible control node SSH pubkey (injected by Terraform into new nodes) |
| `prod/ansible/vault-password` | Ansible Vault file password (`~/.ansible_vault`) |
| `prod/local-runner/ssh-public-key` | Local runner SSH pubkey (copied into Ansible LXC's `authorized_keys`) |
| `prod/freeipa/admin-password` | FreeIPA `admin` user password |
| `prod/freeipa/dm-password` | FreeIPA Directory Manager (LDAP bind) password |
| `prod/super_bot/keytab` | Kerberos keytab for the `super_bot` automation user (base64) |
| `prod/vault/unseal-credentials` | `{"access_key_id": "...", "secret_access_key": "..."}` — AWS KMS auto-unseal for Vault |

---

## Why OIDC instead of long-lived AWS keys

Every workflow that talks to AWS authenticates via GitHub's OIDC provider and
assumes a pre-created IAM role (`GitHubActions-Infrastructure-{env}` or
`GitHubActions-TerraformAdmin-{env}` for IAM-touching jobs). There are **no
long-lived AWS access keys stored anywhere in this repo or in GitHub Secrets**.

Three reasons I chose OIDC:

1. **Nothing to rotate, nothing to leak.** A static access key that lives in a
   GitHub secret is a credential waiting to be exfiltrated — by a compromised
   action, a pushed log line, or an accidental `echo`. OIDC federation mints a
   short-lived STS session on each job run, scoped to exactly the role the
   workflow is allowed to assume. If someone grabs it from a log, the window
   is minutes wide and bounded by one role's policy.

2. **Least-privilege per workflow.** The two IAM roles split the blast radius.
   `GitHubActions-Infrastructure-{env}` can manage VPC, EC2, Secrets Manager
   values, etc. — day-to-day infra. `GitHubActions-TerraformAdmin-{env}`
   can manage IAM and KMS but is only assumed by security-gated workflows
   (that's why the branch path for IAM changes is `dev → dev-security →
   prod-security → prod → main` — extra review before that stronger role
   fires). Roles are Terraform-managed under `terraform/{env}/aws/iam/`.

3. **Permission boundary.** Both roles are pinned under a permissions
   boundary policy that bootstrap-created and that Terraform itself cannot
   remove. So even if a Terraform plan somehow drifted into granting
   something dangerous, the boundary would still block it at apply time.

The price is one extra piece of setup (CloudFormation bootstrap that creates
the OIDC provider + the two roles + the boundary) — but that is a one-shot,
and the rest of the project runs without a single AWS key in sight.

---

## Related Documentation

| Topic | Document |
|-------|----------|
| Workflow patterns | `.github/workflows/workflow-guide.txt` |
| Secret fetching examples | `.github/workflows/README.md` |
| Deployment flow | `github/deployment-pattern.md` |
