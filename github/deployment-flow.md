# Deployment Flow Pattern

## Overview

This document describes the complete deployment workflow for the hybrid-cloud-infrastructure.

---

## Phase 1: Infrastructure (Terraform)

**Runner:** mac-mini (self-hosted)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  1. dev-ansible-full-setup.yml                                              │
│     └── Deploy Ansible LXC → Generate SSH key → Store in AWS                │
│         (dev/ansible/ssh-public-key)                                        │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  2. dev-local-runner-full-setup.yml                                         │
│  3. dev-nginx-full-setup.yml                                                │
│  4. dev-vault-full-setup.yml                                                │
│     └── Fetch Ansible SSH key from AWS → Add to authorized_keys             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Deployment Order

| Order | Workflow | LXC | IP | VLAN |
|-------|----------|-----|-----|------|
| 1 | dev-ansible-full-setup.yml | ansible | 10.0.63.10 | 63 |
| 2 | dev-local-runner-full-setup.yml | local-runner | 10.0.63.20 | 63 |
| 3 | dev-nginx-full-setup.yml | ex-nginx | 10.0.65.10 | 65 |
| 4 | dev-vault-full-setup.yml | vault1,2,3 | 10.0.62.10-12 | 62 |

### SSH Trust (Phase 1 Result)

```
Ansible (10.0.63.10) ──SSH──► local_runner (10.0.63.20)
                      ──SSH──► nginx (10.0.65.10)
                      ──SSH──► vault1,2,3 (10.0.62.10-12)
```

---

## Phase 2: Bootstrap & Services

**Note:** Bootstrap and service setup are now integrated into `*-full-setup.yml` workflows.
Each workflow handles both infrastructure deployment and service configuration.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  dev-ansible-full-setup.yml (4 jobs)                                        │
│     Job 1: Deploy Ansible LXC (Terraform)                                   │
│     Job 2: Add Deploy Key to GitHub                                         │
│     Job 3: Test Git Clone                                                   │
│     Job 4: Setup Ansible                                                    │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  dev-local-runner-full-setup.yml (3 jobs)                                   │
│     Job 1: Deploy Local Runner LXC (Terraform)                              │
│     Job 2: Setup GitHub Actions Runner                                      │
│     Job 3: Install Runner Tools (Ansible)                                   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Summary Table

| Phase | Purpose | Runner | Workflow Pattern |
|-------|---------|--------|------------------|
| Infrastructure + Services | Deploy & Configure | mac-mini / local-runner | `{env}-*-full-setup.yml` |
| AWS Infrastructure | Deploy AWS resources | mac-mini | `{env}-aws-*.yml` |

---

## AWS Secrets Used

| Secret | Created By | Used By |
|--------|------------|---------|
| `dev/ansible/ssh-public-key` | dev-infra-ansible.yml | All other infra workflows |
| `dev/golden-image/lxc-root-password` | Manual (golden template) | All infra workflows (sshpass) |
| `dev/proxmox/terraform-token` | Manual | All infra workflows |

---

## Boot Order (Proxmox)

| Order | LXC | Purpose |
|-------|-----|---------|
| 1 | FreeIPA | Identity/DNS (must start first) |
| 2 | Ansible | Control node |
| 3 | local-runner | GitHub Actions runner |
| 4 | ex-nginx | External reverse proxy |
| 5 | vault1 | Vault cluster node 1 |
| 6 | vault2 | Vault cluster node 2 |
| 7 | vault3 | Vault cluster node 3 |
