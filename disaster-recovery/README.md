# Kubernetes & Vault Cluster — Chaos Engineering Test Plan v5

---

## Real Incidents Before DR Testing

Before the planned DR test phase even began, real production incidents occurred that validated (and exposed gaps in) the architecture. These unplanned failures provided authentic disaster recovery experience:

**Incident 1: Power Outage (April 9, 2026)**
- Triggered 5+ troubleshooting cases
- Exposed UPS monitor cron misconfiguration, VM autostart timing issues, Flux cascade failures
- Related cases: TS-PVE-012, TS-PVE-013, TS-K8S-018, TS-K8S-019

**Incident 2: Prod Worker VM Crash (April 11, 2026)**
- Worker VM crashed ~1 minute after boot, unknown cause
- Exposed remediation pod bug (can't reboot stopped VMs), vault-injector race condition
- Led to architecture improvements: remediation status check, vault-injector moved to masters
- Related cases: TS-PVE-014, TS-K8S-021, TS-K8S-022, TS-K8S-023

**Incident 3: Dev Proxmox Crash During Backup (April 11, 2026)**
- Proxmox host crashed silently during vzdump, unknown cause
- Vault node (vault3) went down, validated 2-node quorum resilience
- Exposed stale Raft data recovery procedure
- Related cases: TS-PVE-015, TS-VLT-005, TS-K8S-024

These real incidents proved more valuable than planned tests because they exposed gaps (like remediation not handling stopped VMs) that careful simulation might have missed.

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