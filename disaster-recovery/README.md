# Kubernetes & Vault Cluster — Chaos Engineering Test Plan v5

---

## How to Use This Plan

Each Task is a failure domain (Compute, Network, Storage, etc.).
Each Task contains numbered **Scenarios** that escalate in severity.
After every Scenario, run the **Observation Checklist** at the bottom of that Task.
Execute Task 0 (Backup & Restore) FIRST — it's your safety net before any destructive testing.

---

## Tasks

| Task | Failure Domain | Scenarios | Prerequisite |
|------|---------------|-----------|--------------|
| [Task 0](task-0-backup-restore/PLAN.md) | Backup & Restore Validation | 0.1 – 0.9 | None (execute first) |
| [Task 1](task-1-kill-compute/PLAN.md) | Kill Compute | 1.1 – 1.21 | Task 0 |
| [Task 2](task-2-kill-network/PLAN.md) | Kill Network | 2.1 – 2.11 | Task 0 |
| [Task 3](task-3-kill-storage/PLAN.md) | Kill Storage | 3.1 – 3.18 | Task 0 |
| [Task 4](task-4-kill-vault/PLAN.md) | Kill Vault | 4.1 – 4.10 | Task 0 |
| [Task 5](task-5-kill-power/PLAN.md) | Kill Power / Infrastructure | 5.1 – 5.7 | Task 0 |

---

## Known SPOFs (Accepted):

- FreeIPA (single instance)
- NAS / NFS storage (single instance)
- External NGINX (single LXC)
- MariaDB (single instance)
- VPN Tunnel
- Router
- Switch
- AP