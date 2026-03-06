# Deployment Flow Pattern

## Overview

This document describes the complete deployment workflow for the hybrid-cloud-infrastructure.

---

## Phase 1: Infrastructure (Terraform)

**Runner:** mac-mini (self-hosted)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  1. dev-infra-ansible.yml                                                   │
│     └── Deploy Ansible LXC → Generate SSH key → Store in AWS                │
│         (dev/ansible/ssh-public-key)                                        │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  2. dev-infra-local_runner.yml                                              │
│  3. dev-infra-nginx.yml                                                     │
│  4. dev-infra-vault_cluster.yml                                             │
│     └── Fetch Ansible SSH key from AWS → Add to authorized_keys             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Deployment Order

| Order | Workflow | LXC | IP | VLAN |
|-------|----------|-----|-----|------|
| 1 | dev-infra-ansible.yml | ansible | 10.0.63.10 | 63 |
| 2 | dev-infra-local_runner.yml | local-runner | 10.0.63.20 | 63 |
| 3 | dev-infra-nginx.yml | ex-nginx | 10.0.65.10 | 65 |
| 4 | dev-infra-vault_cluster.yml | vault1,2,3 | 10.0.62.10-12 | 62 |

### SSH Trust (Phase 1 Result)

```
Ansible (10.0.63.10) ──SSH──► local_runner (10.0.63.20)
                      ──SSH──► nginx (10.0.65.10)
                      ──SSH──► vault1,2,3 (10.0.62.10-12)
```

---

## Phase 2: Bootstrap (Setup)

**Runner:** mac-mini (self-hosted)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  5. dev-svc-gh_deploy_key.yml                                               │
│     └── Fetch Ansible SSH key from AWS                                      │
│     └── Add as GitHub Deploy Key via gh CLI                                 │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  6. dev-svc-gh_runner.yml                                                   │
│     └── Ansible runs playbook on local_runner LXC                           │
│         ├── Install GitHub Actions runner                                   │
│         ├── Configure runner with repo token                                │
│         └── Start runner service                                            │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 3: Services (Ansible Playbooks)

**Runner:** local_runner LXC (self-hosted, after Phase 2)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  7. dev-svc-ansible.yml     → Configure Ansible control node itself        │
│  8. dev-svc-nginx.yml       → Install/configure Nginx reverse proxy        │
│  9. dev-svc-vault.yml       → Install/configure Vault HA cluster           │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Summary Table

| Phase | Purpose | Runner | Workflow Pattern |
|-------|---------|--------|------------------|
| 1. Infrastructure | Deploy LXCs (Terraform) | mac-mini | `dev-infra-*.yml` |
| 2. Bootstrap | Setup GH runner | mac-mini | `dev-svc-gh_*.yml` |
| 3. Services | Configure services (Ansible) | local_runner | `dev-svc-*.yml` |

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
