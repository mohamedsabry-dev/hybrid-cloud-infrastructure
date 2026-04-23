# Ansible & Local Runner - Initial Setup Guide (DEV)

Note: If you face issues during deployment, check the troubleshooting/ folder
for the related technology section. Most common issues have been documented there.
Relevant folders: troubleshooting/github-actions/, troubleshooting/linux/

For manual setup reference: github/internal-runners-setup.md

---

## Overview

This guide covers the setup of the Ansible control node and GitHub Actions
self-hosted runner. These are the FIRST infrastructure nodes deployed after
AWS Secrets, as all other deployments depend on them.

IMPORTANT: Ansible and Local Runner must be deployed BEFORE FreeIPA.

### Why these two come first

These two nodes are how the automation gets a foot inside the env. Everything
that follows — FreeIPA, Vault, Kubernetes, Nginx — needs Ansible running from
somewhere that can actually reach the internal VLANs.

The mac-mini runner cannot do that. It talks to AWS, GitHub, and the Proxmox
API from the outside, so it can create VMs and LXCs via Terraform and it can
run GitHub CLI operations, but it has no route into the workload network
where those newly-created nodes actually live. To configure any host after
it is provisioned, I need a runner inside the env — that is what the Local
Runner LXC is for.

They also depend on each other:
  - The Ansible LXC alone is useless without a way for GitHub Actions to
    trigger it.
  - The Local Runner LXC alone has no repo, no playbooks, no vault password.

So the pair is the bootstrap foot-in-the-door. The mac-mini runner creates
the two LXCs via Terraform, and from that point onward every subsequent
workflow (FreeIPA, Vault, Kubernetes, Nginx) runs on dev-local-runner /
prod-local-runner, which SSHes to the Ansible LXC to execute the actual
playbooks against the internal network.

All subsequent workflows run via these nodes.

---

## Architecture

```
GitHub Actions (mac-mini runner)
        |
        v
   [Ansible LXC]  <---- SSH key stored in AWS, deploy key "ansible-dev" in GitHub
   10.0.63.10            |
        |                |
        v                |
   [Local Runner LXC] ---+  <---- Runs workflows needing local network access
   10.0.63.20
        |
        v
   [All other nodes via Ansible playbooks]
```

### Why two nodes instead of one

I kept the Ansible control node and the GitHub Actions runner as two separate LXCs
on purpose, even though I could have collapsed them into one host. Three reasons:

1. Blast radius. The Ansible LXC holds the repo at /srv/repo and the Ansible Vault
   password file (~/.ansible_vault) — it is effectively the brain of the whole
   environment. The GitHub Actions runner is a separate attack surface: it
   authenticates to GitHub, executes arbitrary workflow YAML, and is reachable
   from outside. If the runner ever gets compromised, I do not want it sitting
   on top of my vault password and my inventory. Keeping them split means the
   runner can only reach Ansible through an explicit SSH hop, not by reading
   local files.

2. User privilege separation. The GitHub runner service runs as an unprivileged
   "runner" user, while the Ansible node uses root for most tasks. Co-locating
   them would force one of two bad compromises — either run the runner as root
   (too much privilege), or grant the "runner" user access to vault credentials
   (also too much). Splitting the two lets each node run at the correct
   privilege level without bending the rules.

3. Lifecycle independence. The GitHub runner registration token expires every
   hour and the runner itself may be re-registered frequently while I am
   iterating on workflows. Keeping it on its own LXC means I can rebuild or
   re-register the runner without touching the Ansible node's repo, SSH keys,
   vault password file, or Galaxy collections.

Trade-off: one extra LXC and an SSH hop per workflow run. Small cost for a much
cleaner security model and a clearer mental picture.

Flow:
    GitHub Actions  -->  Runner LXC  --SSH-->  Ansible LXC  -->  Playbooks on fleet

The runner itself never runs playbooks — it only triggers them on the Ansible
node via SSH. Responsibilities by node:

- Ansible LXC (10.0.63.10): stores the repo (/srv/repo), runs ansible-playbook,
  holds the vault password file, has the GitHub deploy key.
- Local Runner LXC (10.0.63.20): registers with GitHub as a self-hosted runner,
  receives workflow dispatches, SSHes to Ansible to execute playbooks.

---

## Runner Reference

| Environment | IP Address  | Runner Name       | Label             | Purpose                    |
|-------------|-------------|-------------------|-------------------|----------------------------|
| Dev         | 10.0.63.20  | dev-local-runner  | dev-local-runner  | Local network access       |
| Prod        | 10.0.53.20  | prod-local-runner | prod-local-runner | Local network access       |
| Mac Mini    | local       | Mohameds-Mac-mini | mac-mini          | Terraform, GH CLI ops      |

---

## Prerequisites

### AWS Secrets Manager (CRITICAL)

All GitHub workflows depend on secrets stored in AWS Secrets Manager.
These must be created and populated BEFORE deployment.

See: aws-secrets-setup-guide.txt

Required secrets for Ansible/Runner:
- dev/proxmox/terraform-token
- dev/golden-image/lxc-root-password
- dev/ansible/ssh-public-key (auto-populated by workflow)
- dev/local-runner/ssh-public-key (auto-populated by workflow)
- dev/ansible/vault-password

### Golden LXC Template

Before deploying, ensure the golden LXC template exists:

Terraform Path: terraform/dev/proxmox/lxc/golden-template/
Bootstrap Script: proxmox/golden_templates/golden_lxc_setup.sh
GitHub Workflow: .github/workflows/dev-golden-full-setup.yml

### GitHub Secrets and Variables

Required GitHub Secrets:
- AWS_ACCOUNT_ID_DEV
- GH_ADMIN_PAT (for adding deploy key)
- DEV_GH_RUNNER_TOKEN (fresh token from Settings > Actions > Runners)

Required GitHub Variables:
- AWS_REGION_DEV
- DEV_GH_RUNNER_NAME (e.g., "dev-local-runner")
- DEV_GH_RUNNER_LABELS (e.g., "dev-local-runner")

---

## Phase 1: Deploy Ansible LXC

### 1.1 Run Ansible Setup Workflow

Terraform Path: terraform/dev/proxmox/lxc/ansible/

GitHub Workflow: .github/workflows/dev-ansible-full-setup.yml

Gate Locks:
- DEV_INFRA_ANSIBLE_LOCK - Infrastructure deployment
- DEV_SVC_DEPLOY_KEY_LOCK - Deploy key and git clone
- DEV_SVC_ANSIBLE_SETUP_LOCK - Ansible installation

IMPORTANT: Open ALL locks to run full setup in one execution.

### 1.2 Workflow Jobs

**Job 1: Deploy Ansible LXC (DEV_INFRA_ANSIBLE_LOCK)**
- Creates Ansible LXC container via Terraform (unprivileged, nesting enabled)
- Waits for SSH to be ready
- Generates SSH key pair (ed25519) on the LXC
- Stores public key in AWS: dev/ansible/ssh-public-key

**Job 2: Add Deploy Key (DEV_SVC_DEPLOY_KEY_LOCK)**
- Fetches Ansible SSH public key from AWS
- Adds deploy key "ansible-dev" to GitHub repository
- Enables Ansible to clone repo via SSH

**Job 3: Test Git Clone (DEV_SVC_DEPLOY_KEY_LOCK)**
- Adds github.com to known_hosts
- Clones repository to /srv/repo (or pulls if exists)
- Verifies SSH authentication works

**Job 4: Setup Ansible (DEV_SVC_ANSIBLE_SETUP_LOCK)**
- Installs ansible-core and python3-pip
- Pulls latest code
- Creates vault password file (~/.ansible_vault)
- Runs ansible_setup.yml (installs packages and collections)

For more details, see: ansible/dev/playbooks/ansible/README.md

### 1.3 What ansible_setup.yml Does

- Installs initial packages (vim, git, curl, htop, unzip)
- Installs Ansible collections (freeipa, hashi_vault, general, crypto, posix)

Collections path: ansible/dev/playbooks/ansible/templates/requirements.yml

---

## Phase 2: Deploy Local Runner LXC

### 2.1 Run Local Runner Setup Workflow

Terraform Path: terraform/dev/proxmox/lxc/local_runner/

GitHub Workflow: .github/workflows/dev-local-runner-full-setup.yml

Gate Locks:
- DEV_INFRA_LOCAL_RUNNER_LOCK - Infrastructure deployment
- DEV_SVC_GH_RUNNER_LOCK - GitHub runner configuration
- DEV_SVC_LOCAL_RUNNER_TOOLS_LOCK - Tools installation

IMPORTANT: Open ALL locks to run full setup in one execution.

### 2.2 Workflow Jobs

**Job 1: Deploy Local Runner LXC (DEV_INFRA_LOCAL_RUNNER_LOCK)**
- Creates Local Runner LXC container via Terraform (unprivileged, nesting enabled)
- Injects Ansible SSH public key (fetched from AWS) for access
- Generates SSH key pair on the runner
- Stores public key in AWS: dev/local-runner/ssh-public-key
- Copies runner SSH key to Ansible LXC authorized_keys

**Job 2: Setup GitHub Actions Runner (DEV_SVC_GH_RUNNER_LOCK)**
- Creates "runner" user
- Downloads GitHub Actions runner binary (v2.331.0)
- Copies root SSH keys to runner user (for SSH access)
- Configures runner with token, name, and labels
- Installs and starts runner service

**Job 3: Install Runner Tools (DEV_SVC_LOCAL_RUNNER_TOOLS_LOCK)**
- Runs on the newly configured dev-local-runner
- SSHs to Ansible to run setup_tools.yml playbook
- Installs AWS CLI

For more details, see: ansible/dev/playbooks/local-runner/README.md

### 2.3 GitHub Runner Token

The runner requires a fresh registration token:

1. Go to: GitHub repo > Settings > Actions > Runners
2. Click "New self-hosted runner"
3. Copy the token from the configure command
4. Add as secret: DEV_GH_RUNNER_TOKEN

Note: Tokens expire after 1 hour. Generate fresh token before running workflow.

---

## Phase 3: Verification

### 3.1 Verify Ansible LXC

  ssh root@10.0.63.10

  ansible --version
  ls -la /srv/repo/
  ls -la ~/.ansible_vault
  ansible-galaxy collection list | grep freeipa

### 3.2 Verify Local Runner

Check runner status in GitHub:
- Go to: GitHub repo > Settings > Actions > Runners
- Should see "dev-local-runner" with "Idle" status

  ssh root@10.0.63.20

  systemctl status actions.runner.*
  ssh root@10.0.63.10 "hostname"    # Test SSH to Ansible

### 3.3 Runner Service Commands

  cd /opt/actions-runner
  ./svc.sh status    # Check status
  ./svc.sh stop      # Stop runner
  ./svc.sh start     # Start runner

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Token expired/invalid | Generate fresh token (expires in 1 hour) |
| Runner exists with same name | Use --replace flag (workflow does this) |
| Orphaned config | Delete .runner, .credentials files in /opt/actions-runner |
| Session conflict | Delete runner from GitHub UI first |
| Runner can't SSH to Ansible | Copy root SSH keys to runner user |

For more troubleshooting, see: github/internal-runners-setup.md

---

## How Workflows Use These Nodes

```yaml
# Terraform deployments, GH CLI operations
runs-on: mac-mini

# Ansible playbooks needing local network (dev)
runs-on: dev-local-runner

# Ansible playbooks needing local network (prod)
runs-on: prod-local-runner
```

---

## Summary - File Reference

| Component                | Path                                                |
|--------------------------|-----------------------------------------------------|
| Ansible LXC TF           | terraform/dev/proxmox/lxc/ansible/                  |
| Local Runner LXC TF      | terraform/dev/proxmox/lxc/local_runner/             |
| Ansible Setup Workflow   | .github/workflows/dev-ansible-full-setup.yml        |
| Runner Setup Workflow    | .github/workflows/dev-local-runner-full-setup.yml   |
| Ansible Setup Playbook   | ansible/dev/playbooks/ansible/ansible_setup.yml     |
| Runner Tools Playbook    | ansible/dev/playbooks/local-runner/setup_tools.yml  |
| Ansible Collections      | ansible/dev/playbooks/ansible/templates/requirements.yml |
| Manual Setup Guide       | github/internal-runners-setup.md                    |
| Group Vars (all)         | ansible/dev/inventory/group_vars/all.yml            |

---

## AWS Secrets Reference

| Secret                             | Purpose                              |
|------------------------------------|--------------------------------------|
| dev/proxmox/terraform-token        | Proxmox API credentials              |
| dev/golden-image/lxc-root-password | LXC root password                    |
| dev/ansible/ssh-public-key         | Ansible SSH key (auto-populated)     |
| dev/local-runner/ssh-public-key    | Runner SSH key (auto-populated)      |
| dev/ansible/vault-password         | Ansible Vault encryption password    |

---

## GitHub Secrets/Variables Reference

| Secret/Variable         | Type     | Purpose                              |
|-------------------------|----------|--------------------------------------|
| AWS_ACCOUNT_ID_DEV      | Secret   | AWS account for OIDC auth            |
| GH_ADMIN_PAT            | Secret   | PAT for adding deploy key            |
| DEV_GH_RUNNER_TOKEN     | Secret   | Runner registration token            |
| AWS_REGION_DEV          | Variable | AWS region                           |
| DEV_GH_RUNNER_NAME      | Variable | Runner name (e.g., dev-local-runner) |
| DEV_GH_RUNNER_LABELS    | Variable | Runner labels for workflow targeting |

---

## Gate Locks Reference

| Lock                           | Controls                              |
|--------------------------------|---------------------------------------|
| DEV_INFRA_ANSIBLE_LOCK         | Ansible LXC deployment                |
| DEV_SVC_DEPLOY_KEY_LOCK        | Deploy key and git clone              |
| DEV_SVC_ANSIBLE_SETUP_LOCK     | Ansible package installation          |
| DEV_INFRA_LOCAL_RUNNER_LOCK    | Local Runner LXC deployment           |
| DEV_SVC_GH_RUNNER_LOCK         | GitHub runner configuration           |
| DEV_SVC_LOCAL_RUNNER_TOOLS_LOCK| Runner tools installation             |

Set lock to 'true' to skip, 'false' or unset to run.

---

## Deployment Order

Complete deployment order:

0. AWS Secrets (see aws-secrets-setup-guide.txt)
1. Ansible + Local Runner (this guide)
2. FreeIPA (see freeipa-initial-setup-guide.txt)
3. Vault (see vault-initial-setup-guide.txt)
4. Kubernetes (see k8s-initial-setup-guide.txt)

---
