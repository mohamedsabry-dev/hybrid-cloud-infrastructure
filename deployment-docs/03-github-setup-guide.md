# GitHub Repository & Workflows - Setup Guide

Note: If you face issues during deployment, check the troubleshooting/ folder
for the related technology section. Most common issues have been documented there.
Relevant folders: troubleshooting/github/

For more details, see: github/README.md

---

## Overview

This guide covers the GitHub repository setup including branch strategy, secrets,
variables, workflow locks, and self-hosted runners required for the hybrid cloud
infrastructure automation.

IMPORTANT: GitHub setup must be completed AFTER AWS Bootstrap but BEFORE any
infrastructure deployment workflows.

---

## Branch Strategy

| Branch          | Purpose                          | Trusted IAM Role              |
|-----------------|----------------------------------|-------------------------------|
| main            | Clean merges only (no workflow)  | None                          |
| dev             | Development infra deploys        | GitHubActions-Infrastructure-dev |
| prod            | Production infra deploys         | GitHubActions-Infrastructure-prod |
| dev-security    | Dev IAM/security changes         | GitHubActions-TerraformAdmin-dev |
| prod-security   | Prod IAM/security changes        | GitHubActions-TerraformAdmin-prod |

For more details, see: github/README.md

---

## Deployment Flow Patterns

### Standard Changes (No IAM)

Path: dev → prod → main

```
dev (push) → Test → prod (PR) → main (PR)
    │                  │            │
    ▼                  ▼            ▼
Infrastructure-dev  Infrastructure-prod  Milestone
```

### IAM/Security Changes

Path: dev → dev-security → prod-security → prod → main

```
dev → dev-security (PR) → prod-security (PR) → prod (PR) → main
           │                     │
           ▼                     ▼
    TerraformAdmin-dev     TerraformAdmin-prod
```

For more details, see: github/deployment-pattern.md

---

## Phase 1: Configure GitHub Secrets

Location: GitHub repo → Settings → Secrets and variables → Actions → Secrets

### Required Secrets

| Secret                  | Purpose                                |
|-------------------------|----------------------------------------|
| AWS_ACCOUNT_ID_DEV      | Dev AWS account ID for OIDC            |
| AWS_ACCOUNT_ID_PROD     | Prod AWS account ID for OIDC           |
| GH_ADMIN_PAT            | Fine-grained PAT for deploy keys       |
| DEV_GH_RUNNER_TOKEN     | Dev runner token (expires ~1 hour)     |
| PROD_GH_RUNNER_TOKEN    | Prod runner token (expires ~1 hour)    |
| HOME_PUBLIC_IP          | Home IP for AWS security groups        |
| VPN_PUBLIC_KEY_DEV      | Dev VPN EC2 SSH key                    |
| VPN_PUBLIC_KEY_PROD     | Prod VPN EC2 SSH key                   |
| GH_ADMIN_PAT_FLUX       | GitHub PAT for FluxCD                  |
| GH_USERNAME             | GitHub username for Flux               |

For more details, see: github/variables-secrets.md

---

## Phase 2: Configure GitHub Variables

Location: GitHub repo → Settings → Secrets and variables → Actions → Variables

### Region Variables

| Variable         | Value      |
|------------------|------------|
| AWS_REGION_DEV   | us-east-1  |
| AWS_REGION_PROD  | eu-west-2  |

### Runner Variables

| Variable                | Value             |
|-------------------------|-------------------|
| DEV_GH_RUNNER_NAME      | dev-local-runner  |
| DEV_GH_RUNNER_LABELS    | dev-local-runner  |
| PROD_GH_RUNNER_NAME     | prod-local-runner |
| PROD_GH_RUNNER_LABELS   | prod-local-runner |

---

## Phase 3: Configure Workflow Lock Variables

### Lock Pattern

Pattern: {ENV}_INFRA_{NAME}_LOCK or {ENV}_SVC_{NAME}[_LOCK]

Note: naming is inconsistent — older SVC vars (FREEIPA_SETUP, VAULT_SETUP,
K8S_CLUSTER_SETUP) never got the _LOCK suffix. Newer ones have it. Both
work the same way.

| Value   | Behavior                    |
|---------|-----------------------------|
| true    | Job skips (safe default)    |
| false   | Job runs on push            |

### How to Trigger a Workflow

1. Set lock variable to "false" in GitHub UI
2. Push to branch (workflow runs)
3. Set variable back to "true" (re-lock)

Note: Golden template workflows auto-lock after success.

### DEV Lock Variables

| Variable                         | Controls                    |
|----------------------------------|-----------------------------|
| DEV_INFRA_GOLDEN_VM_LOCK         | Golden VM template          |
| DEV_INFRA_GOLDEN_LXC_LOCK        | Golden LXC template         |
| DEV_INFRA_ANSIBLE_LOCK           | Ansible LXC deployment      |
| DEV_INFRA_LOCAL_RUNNER_LOCK      | Local Runner LXC deployment |
| DEV_INFRA_FREEIPA_LOCK           | FreeIPA VM deployment       |
| DEV_INFRA_VAULT_CLUSTER_LOCK     | Vault cluster deployment    |
| DEV_INFRA_NGINX_LOCK             | Nginx LXC deployment        |
| DEV_INFRA_K8S_MASTERS_LOCK       | K8s masters deployment      |
| DEV_INFRA_K8S_WORKERS_LOCK       | K8s workers deployment      |
| DEV_SVC_K8S_CLUSTER_SETUP        | K8s cluster setup playbooks |
| DEV_PROXMOX_STORAGE_NAS_CONFIG   | Proxmox NAS storage         |
| DEV_SVC_DEPLOY_KEY_LOCK          | Deploy key setup            |
| DEV_SVC_ANSIBLE_SETUP_LOCK       | Ansible package setup       |
| DEV_SVC_GH_RUNNER_LOCK           | GitHub runner setup         |
| DEV_SVC_LOCAL_RUNNER_TOOLS_LOCK  | Runner tools install        |
| DEV_SVC_FREEIPA_SETUP            | FreeIPA service setup       |
| DEV_SVC_VAULT_SETUP              | Vault service setup         |

### PROD Lock Variables

Same pattern as DEV with PROD_ prefix.

---

## Phase 4: Setup Self-Hosted Runners

### Runner Reference

| Environment | IP Address  | Runner Name       | Label             | Purpose                    |
|-------------|-------------|-------------------|-------------------|----------------------------|
| Mac Mini    | local       | Mohameds-Mac-mini | mac-mini          | Terraform, GH CLI ops      |
| Dev         | 10.0.63.20  | dev-local-runner  | dev-local-runner  | Dev playbooks via Ansible  |
| Prod        | 10.0.53.20  | prod-local-runner | prod-local-runner | Prod playbooks via Ansible |

### 4.1 Mac Mini Runner Setup

The Mac Mini is the primary runner for Terraform and GitHub CLI operations.

| Setting          | Value                       |
|------------------|-----------------------------|
| Runner Name      | Mohameds-Mac-mini           |
| Location         | ~/WorkSpace/actions-runner  |
| OS               | macOS (Darwin, ARM64)       |
| Runner Version   | v2.331.0                    |

**Installation:**

  mkdir -p ~/WorkSpace/actions-runner && cd ~/WorkSpace/actions-runner
  # Download: actions-runner-osx-arm64-2.331.0.tar.gz
  ./config.sh --url <repo-url> --token <TOKEN> \
      --labels self-hosted,macOS,ARM64,mac-mini --name Mohameds-Mac-mini
  ./svc.sh install && ./svc.sh start

**Required Tools:**

| Tool       | Purpose                              |
|------------|--------------------------------------|
| Terraform  | Infrastructure provisioning          |
| AWS CLI    | AWS resource management              |
| Ansible    | Configuration management             |
| Docker     | Container builds                     |
| Python     | Automation scripts                   |
| sshpass    | SSH password auth for LXC            |
| gh CLI     | GitHub API operations                |
| PowerShell | VMware/Windows automation (optional) |

**Provider Mirror:** Terraform providers cached locally at ~/.terraform.d/providers-mirror

**Service Commands:**

  ./svc.sh status    # Check runner status
  ./svc.sh stop      # Stop runner
  ./svc.sh start     # Start runner

**Network Route (10.x access):**

Mac Mini needs a route to reach on-premises 10.x networks:

  cd workstation/route-setup
  sudo ./install-route.sh

This adds persistent route 10.0.0.0/8 via local gateway using launchd service.

For more details, see: github/runner-mac-mini.md and workstation/README.md

### 4.2 Local Runner Setup (Automated)

Local runners are set up automatically via workflows after Ansible LXC is deployed.

Workflow: .github/workflows/dev-local-runner-full-setup.yml

Prerequisites:
- Fresh runner token in DEV_GH_RUNNER_TOKEN (expires ~1 hour)
- Variables: DEV_GH_RUNNER_NAME, DEV_GH_RUNNER_LABELS

For manual setup reference, see: github/internal-runners-setup.md

### 4.3 Using Runners in Workflows

```yaml
# Terraform deployments, GH CLI operations
runs-on: mac-mini

# Ansible playbooks needing local network (dev)
runs-on: dev-local-runner

# Ansible playbooks needing local network (prod)
runs-on: prod-local-runner
```

---

## Phase 5: Verify Setup

### 5.1 Verify Runners

Go to: GitHub repo → Settings → Actions → Runners

Expected runners:
- Mohameds-Mac-mini (Idle)
- dev-local-runner (Idle) - after deployment
- prod-local-runner (Idle) - after deployment

### 5.2 Verify Lock Variables

Go to: GitHub repo → Settings → Secrets and variables → Actions → Variables

All lock variables should be set to "true" by default.

---

## Secret Flow Architecture

```
GitHub Secrets (Settings -> Actions -> Secrets)
    +-- GH_ADMIN_PAT         (Ansible deploy key)
    +-- DEV_GH_RUNNER_TOKEN  (Runner registration)
    +-- AWS_ACCOUNT_ID_DEV   (OIDC assume role)

                    │
                    ▼

AWS Secrets (fetched at runtime via OIDC)
    +-- dev/proxmox/terraform-token
    +-- dev/ansible/ssh-public-key
    +-- dev/super_bot/keytab

                    │
                    ▼

Flow: OIDC → AWS → Secrets Manager → Mask → TF_VAR → Terraform
```

---

## Code Architecture: Copy-Promote Pattern

### Folder Isolation

```
terraform/dev/aws/secrets/     <- DEV code (develop here)
terraform/prod/aws/secrets/    <- PROD code (copy when ready)

ansible/dev/playbooks/         <- DEV playbooks
ansible/prod/playbooks/        <- PROD playbooks

.github/workflows/dev-*.yml    <- DEV workflows
.github/workflows/prod-*.yml   <- PROD workflows
```

### Why Copy-Promote?

Problem with shared code: If halfway through developing a feature in dev branch,
then need to merge OTHER completed work to prod - the incomplete work comes along.

With folder isolation: Work stays isolated until explicitly copied to prod.

### DEV → PROD Promotion

1. Complete and test feature in dev folder
2. Copy to prod folder, update env-specific values
3. Diff to verify only expected changes
4. Commit and push to prod branch

### Expected Differences Between Environments

- Environment tags: "dev" vs "prod"
- IP ranges: 10.0.6x.x vs 10.0.5x.x
- Secret paths: dev/* vs prod/*
- State bucket names: *-dev vs *-prod
- Role names: *-dev vs *-prod
- Branch triggers: dev vs prod

---

## Summary - File Reference

| Component                  | Path                                    |
|----------------------------|-----------------------------------------|
| GitHub Folder Overview     | github/README.md                        |
| Variables & Secrets        | github/variables-secrets.md             |
| Deployment Pattern         | github/deployment-pattern.md            |
| Deployment Flow            | github/deployment-flow.md               |
| Mac Mini Runner            | github/runner-mac-mini.md               |
| Internal Runners Setup     | github/internal-runners-setup.md        |
| Workflow Guide             | .github/workflows/workflow-guide.txt    |
| Workflow README            | .github/workflows/README.md             |
| Mac Mini Workstation       | workstation/README.md                   |
| Route Setup Scripts        | workstation/route-setup/                |

---

## Quick Reference - Workflow File Naming

| Pattern                    | Purpose                                 |
|----------------------------|-----------------------------------------|
| dev-aws-*.yml              | AWS resource deployment                 |
| dev-*-full-setup.yml       | Infrastructure + service setup          |
| dev-golden-*.yml           | Golden template creation                |
| prod-*.yml                 | Production equivalents                  |

---

## Troubleshooting

| Issue                           | Solution                                    |
|---------------------------------|---------------------------------------------|
| Token expired/invalid           | Generate fresh token (expires in ~1 hour)   |
| Runner exists with same name    | Use --replace flag (workflow does this)     |
| Orphaned config                 | Delete .runner, .credentials files          |
| Session conflict                | Delete runner from GitHub UI first          |
| Runner can't SSH to Ansible     | Copy root SSH keys to runner user           |
| Workflow not triggering         | Check lock variable is set to "false"       |

For more troubleshooting, see: github/internal-runners-setup.md

---

## Troubleshooting Reference

Key GitHub troubleshooting cases, all under troubleshooting/github/:

| TS case | File | Summary |
|---------|------|---------|
| TS-GH-001 | 1-github-runner-stuck-job.md | Runner not starting after reboot — service not installed as persistent daemon |
| TS-GH-002 | 2-workflow-lock-flag-pattern.md | Terraform workflows triggered on push destroy resources — drove the lock flag pattern |
| TS-GH-005 | 5-runner-clock-skew-auth-failure.md | Runner offline with "registration deleted" — clock skew from broken DNS/NTP |
| TS-GH-007 | 7-concurrent-terraform-workflow-lxc-reboot.md | Vault workflow exit 255 — concurrent Terraform workflows rebooted LXCs |

---

## Deployment Order

GitHub setup is step 3 — after network, Proxmox, and AWS bootstrap. For the
full 0–15 sequence, see [README.md](README.md).

---
