# AWS Secrets Manager - Setup Guide (DEV)

Note: If you face issues during deployment, check the troubleshooting/ folder
for the related technology section.
Relevant folders: troubleshooting/aws/, troubleshooting/github/

---

## Overview

This guide covers the setup of AWS Secrets Manager secrets that are required
by ALL GitHub workflows. These secrets store credentials, API tokens, passwords,
and keys that are fetched at runtime during infrastructure deployments.

IMPORTANT: This runs AFTER the one-time AWS CloudFormation bootstrap
(see 02-aws-bootstrap-setup-guide.md) but BEFORE any other infrastructure
deployment. All subsequent workflows depend on these secrets existing AND
being populated with real values.

---

### A note for anyone implementing this

The specific secret names, naming convention (`{env}/<service>/<kind>`), and
the two-phase "Terraform creates placeholders → you populate manually" model
are choices I landed on. They are not requirements of AWS Secrets Manager
itself — you can flatten the namespace, use different delimiters, or skip the
two-phase model (e.g. inject values directly via Terraform variables) if that
fits your context.

Why I went with placeholders + manual fill: it keeps secret values entirely
out of Terraform state and out of git. Terraform owns the secret's identity,
lifecycle, tags, and permissions; a human populates the actual secret body
once, out-of-band via `aws secretsmanager put-secret-value`. Terraform never
sees the real value, so a leaked state file contains no secrets.

Prod mirrors dev: the same secret names and the same Terraform module exist
under `terraform/prod/aws/secrets/` and `.github/workflows/prod-aws-secrets.yml`,
produce the same set of secrets with the `prod/` prefix. Everything in this
guide applies to prod with `dev` → `prod` substitution throughout.

---

## Prerequisites

Before deploying secrets:

1. **AWS CloudFormation bootstrap completed** — OIDC provider, state backend,
   TerraformAdmin role, and PermissionsBoundary all in place. See
   `02-aws-bootstrap-setup-guide.md` + the "Why this architecture" reasoning
   in `aws/DESIGN.md`.
2. **IAM role** `GitHubActions-Infrastructure-dev` exists with Secrets Manager
   permissions (created by the `aws-iam` workflow on `dev-security` branch —
   that's part of the bootstrap phase, not this one).
3. **GitHub repo secrets** configured — `AWS_ACCOUNT_ID_DEV`.
4. **GitHub repo variables** configured — `AWS_REGION_DEV`.

The complete GitHub secrets/vars reference lives in `github/variables-secrets.md`.

---

## Phase 1: Deploy Secret Placeholders (Terraform)

### 1.1 Run Secrets Workflow

Terraform Path: terraform/dev/aws/secrets/

GitHub Workflow: .github/workflows/dev-aws-secrets.yml

This workflow creates the secret *resources* in AWS Secrets Manager — but
with placeholder bodies. Terraform owns the resource lifecycle and
permissions; the actual secret bodies are populated manually in Phase 2 so
that real credentials never enter Terraform state.

  # Trigger via GitHub Actions UI or push to dev branch
  # Path trigger: terraform/dev/aws/secrets/**

### 1.2 Secrets Created

The workflow creates the following secrets (with placeholder values):

| Secret Name                        | Purpose                              |
|------------------------------------|--------------------------------------|
| dev/proxmox/terraform-token        | Proxmox API token (JSON: token_id, token_secret) |
| dev/proxmox/ssh-admin-dev-password | Proxmox node SSH admin password      |
| dev/golden-image/vm-root-password  | VM template root password            |
| dev/golden-image/lxc-root-password | LXC template root password           |
| dev/ansible/ssh-public-key         | Ansible SSH public key for node access |
| dev/local-runner/ssh-public-key    | Local runner SSH public key          |
| dev/freeipa/admin-password         | FreeIPA admin user password          |
| dev/freeipa/dm-password            | FreeIPA Directory Manager password   |
| dev/super_bot/keytab               | Kerberos keytab for super_bot (base64) |
| dev/ansible/vault-password         | Ansible Vault encryption password    |
| dev/vm/break-glass-password        | Emergency break-glass user password (placeholder for the `gandalf` user — break-glass playbook is still a TODO stub in `ansible/*/playbooks/common/setup_breakglass.yml`) |

---

## Phase 2: Populate Secrets with Real Values

### 2.1 Update Secrets via AWS CLI

After the workflow creates placeholders, update each secret with actual values:

**For JSON secrets (multiple key-value pairs):**

  aws secretsmanager put-secret-value \
    --secret-id dev/proxmox/terraform-token \
    --secret-string '{"token_id":"terraform@pam!token-name","token_secret":"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"}'

**For single-value secrets:**

  aws secretsmanager put-secret-value \
    --secret-id dev/golden-image/vm-root-password \
    --secret-string 'your-secure-password'

  aws secretsmanager put-secret-value \
    --secret-id dev/ansible/ssh-public-key \
    --secret-string 'ssh-ed25519 AAAAC3... user@host'

### 2.2 Secret Value Formats

| Secret                             | Format                               |
|------------------------------------|--------------------------------------|
| dev/proxmox/terraform-token        | JSON: {"token_id":"...","token_secret":"..."} |
| dev/proxmox/ssh-admin-dev-password | Plain text password                  |
| dev/golden-image/vm-root-password  | Plain text password                  |
| dev/golden-image/lxc-root-password | Plain text password                  |
| dev/ansible/ssh-public-key         | SSH public key (ssh-ed25519 AAAA...) |
| dev/local-runner/ssh-public-key    | SSH public key (ssh-ed25519 AAAA...) |
| dev/freeipa/admin-password         | Plain text password                  |
| dev/freeipa/dm-password            | Plain text password                  |
| dev/super_bot/keytab               | Base64-encoded keytab file           |
| dev/ansible/vault-password         | Plain text password                  |
| dev/vm/break-glass-password        | Plain text password                  |

### 2.3 Verify Secrets

List all dev secrets:

  aws secretsmanager list-secrets \
    --query "SecretList[?starts_with(Name,'dev/')].Name" \
    --output table

Retrieve a secret value (for verification):

  aws secretsmanager get-secret-value \
    --secret-id dev/proxmox/terraform-token \
    --query SecretString --output text

---

## Phase 3: Additional Secrets (Created by Other Workflows)

Some secrets are created by other workflows, not by the secrets workflow:

### 3.1 Vault Unseal Credentials

Created by: .github/workflows/dev-aws-kms-vault-unseal.yml
Terraform: terraform/dev/aws/kms-vault-unseal/

Secret: dev/vault/unseal-credentials
Format: JSON {"access_key_id":"...","secret_access_key":"..."}

This is created automatically when you deploy the KMS unseal infrastructure.

### 3.2 Vault Init Keys

Created by: Manual (after vault operator init)

Secret: dev/vault/init-keys
Format: Plain text (copy entire init output)

This must be manually created after initializing Vault.

---

## Secret Dependencies by Service

### FreeIPA Deployment
Required secrets:
- dev/proxmox/terraform-token
- dev/ansible/ssh-public-key
- dev/golden-image/vm-root-password
- dev/freeipa/admin-password
- dev/freeipa/dm-password

### Vault Deployment
Required secrets:
- dev/proxmox/terraform-token
- dev/ansible/ssh-public-key
- dev/golden-image/lxc-root-password
- dev/super_bot/keytab
- dev/vault/unseal-credentials (from KMS workflow)

### Kubernetes Deployment
Required secrets:
- dev/proxmox/terraform-token
- dev/ansible/ssh-public-key
- dev/golden-image/vm-root-password
- dev/super_bot/keytab

GitHub Secrets also required:
- GH_ADMIN_PAT_FLUX (for FluxCD)
- GH_USERNAME

---

## Summary - File Reference

| Component              | Path                                            |
|------------------------|-------------------------------------------------|
| Secrets Terraform      | terraform/dev/aws/secrets/                      |
| Secrets Workflow       | .github/workflows/dev-aws-secrets.yml           |
| KMS Unseal Terraform   | terraform/dev/aws/kms-vault-unseal/             |
| KMS Unseal Workflow    | .github/workflows/dev-aws-kms-vault-unseal.yml  |
| AWS architecture story | aws/DESIGN.md                                   |
| AWS bootstrap ops ref  | aws/bootstrap.md                                |
| GitHub repo secrets    | github/variables-secrets.md                     |

---

## Deployment Order

AWS Secrets is step 4 — after network, Proxmox, AWS bootstrap, and GitHub
setup. For the full 0–15 sequence, see [README.md](README.md).

---
