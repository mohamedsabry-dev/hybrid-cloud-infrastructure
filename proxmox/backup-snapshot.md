# Proxmox Backup & Snapshot Guide
> Homelab Hybrid Cloud — Dev & Prod Environments

---

## Overview

| Feature | Tool | Managed By |
|---|---|---|
| NFS Storage Mount | Terraform | Code |
| Backup Retention Policy | Terraform | Code |
| Backup Job Schedule | PVE GUI | Manual (one-time) |
| Snapshots | PVE GUI | Manual (event-driven) |

---

## 1. Backup

### Strategy
- **Backup mode:** `snapshot` — VMs/LXCs stay running, no downtime
- **Schedule:** Sunday 02:00 weekly
- **Retention:** `keep_last = 1` per environment (storage constraint)
- **Target:** NAS via NFS on VLAN 40 (storage network)

### What Gets Backed Up
All nodes — including stateless ones, because NAS storage carries the data disk partitions.

### Backup Groups & Timing
Workers are large (80GB data disk each) so they get dedicated slots:

| Group | Nodes | Time |
|---|---|---|
| Group 1 | Vault 1,2,3 + Masters 1,2,3 | 01:00 |
| Group 2 | Worker 1 | 02:00 |
| Group 3 | Worker 2 | 02:30 |
| Group 4 | Worker 3 | 03:00 |
| Group 5 | IPA + NGINX + Ansible + GH Runner | 03:30 |

### NFS Storage — Terraform Config

**Storage allocation:**
| Share | Size | Environment |
|---|---|---|
| `/volume1/shared-iso` | ~50GB | Both (ISO, CT templates) |
| `/volume1/prod-storage` | ~600GB | Prod (disks + backups) |
| `/volume1/dev-storage` | ~400GB | Dev (disks + backups) |


### Backup Job — PVE GUI (One-Time Setup)
Terraform provider (BPG 0.96.0) does not support backup job scheduling. Configure manually:

```
Datacenter → Backup → Add
  Schedule:  Sun 02:00
  Mode:      snapshot
  Storage:   nas-dev-data / nas-prod-data
  Max Files: 1
  Select:    All VMs/LXCs
```

This config persists in `/etc/pve/jobs.cfg` permanently.

### Backup Mode Reference
| Mode | VM State | Use Case |
|---|---|---|
| `snapshot` | Stays running | Standard — production pattern |
| `suspend` | Briefly pauses | Avoid — worst of both worlds |
| `stop` | Shuts down | Cleanest but causes downtime |

> **Why snapshot mode is safe at 2AM:** Vault (raft), IPA (LDAP), and etcd have near-zero active writes. Low consistency risk.

> **QEMU Guest Agent:** Install on all VMs for application-consistent snapshots (flushes writes before PVE snapshots). Not applicable to LXCs.

---

## 2. Snapshots

### Strategy
Snapshots are **event-driven, not scheduled** — taken manually before any risky operation.

### When to Take a Snapshot
- Before Vault setup begins
- Before K8s cluster setup begins
- Before any major Ansible playbook run on critical VMs
- Before OS/kernel upgrades

### How to Take a Snapshot
```
PVE GUI → VM/LXC → Snapshots → Take Snapshot
  Name: pre-<phase>-<date>
  Example: pre-vault-setup-2025-01-15
           pre-k8s-setup-2025-01-20
           pre-ipa-upgrade-2025-02-01
```

### Checkpoint Pattern (Learning Workflow)
```
VM provisioned + IPA enrolled + basics configured
        ↓
    SNAPSHOT  ←  "clean baseline"
        ↓
    Attempt setup (fail → learn → retry)
        ↓
    Revert to snapshot if needed → try again
```

This avoids manually cleaning up failed attempts and gives a guaranteed clean state.

