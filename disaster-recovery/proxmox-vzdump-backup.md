DR Test: Proxmox VM/LXC Backup Validation
Date: 2026-04-11
Result: PASS
_____________________________________________________________________

[Info]
Domain: Proxmox / vzdump / NAS Storage
Environment: DEV (pve-dev) + PROD (pve-prod) — 9 VMs + 7 LXCs each
Triggered by: Need validated backups before DR testing begins, and need
  to confirm snapshot-mode backup doesn't disrupt running workloads

_____________________________________________________________________

[Planned Scope]

Run vzdump snapshot-mode backup of all VMs and LXCs on both Proxmox
hosts. Verify all backups complete successfully, check file sizes are
reasonable, and observe whether running k8s workloads are affected
during the backup window.

_____________________________________________________________________

[Pre-State]

All VMs and LXCs running on both hosts. K8s cluster healthy (6 nodes
Ready), WordPress serving, MariaDB operational. Golden images (9000,
9001, 9010) are shutdown Terraform templates — backed up but not running.

_____________________________________________________________________

[Test 1.1 — Full backup on both hosts]

Action:
  Triggered vzdump backup jobs via Proxmox:
  - pve-prod: 12:19 → 12:29 (~10 min), storage: nas-prod-data
  - pve-dev: 14:11 → 14:21 (~10 min), storage: nas-dev-data

What happened:
  All 16 items backed up successfully on each host. No failures.

  Sizes — VMs: 1.4G–6.6G (workers largest due to container runtime data),
  LXCs: 223M–1.2G (local-runner largest). Total: ~35GB dev, ~30GB prod.

  Dev had a second backup run because a mid-backup crash happened earlier
  that day (see TS-PVE-015). The 14:11 run was the clean one.

_____________________________________________________________________

[Test 1.2 — Live workload impact during backup (observed 2026-04-13)]

Why this test: vzdump uses a brief lock/suspend phase per VM for
  snapshot consistency. Does this affect k8s workloads?

Action:
  Observed cluster during a subsequent backup run. Worker2 and worker3
  went through the lock/suspend phase while running WordPress and
  MariaDB pods.

What happened:
  - All 6 k8s nodes stayed Ready throughout
  - kubectl exec into WordPress and MariaDB pods worked during backup
  - WordPress web UI accessible (login + browsing)
  - MariaDB connections uninterrupted
  - Zero pod restarts during backup window

What this tells me:
  Proxmox vzdump snapshot mode is non-disruptive. The lock phase is
  brief enough that kubelet heartbeats don't miss, pods don't notice,
  and users see no impact. Safe for production hours.

_____________________________________________________________________

[Findings]

1. vzdump snapshot-mode backup completes in ~10 minutes for the full
   environment (9 VMs + 7 LXCs). Non-disruptive to running workloads.

2. Worker VMs are the largest backups (6+ GB) due to container runtime
   data. LXCs are small (< 1.2G). Total footprint ~30-35GB per host.

3. Golden images (shutdown templates) back up fine — they're just disk
   snapshots. No special handling needed.

_____________________________________________________________________

[References]

- TS-PVE-015 — mid-backup crash incident (why dev has double backups)
- nas-dev-data:/dump/ — dev backup storage
- nas-prod-data:/dump/ — prod backup storage
