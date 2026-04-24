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

[Test 1.3 — Live incident: thermal shutdown + master degradation (2026-04-23)]

Why this test: Real incident, not planned. Backup ran on both dev and prod
  at the same scheduled time. Two separate failures observed with different
  root causes.

What happened:
  PROD (pve-prod):
  - Backup started 21:00, completed 4 VMs (freeipa + 3 masters) successfully
  - During worker1 backup, CPU spiked to 91°C from zstd compression load
  - temperature_monitor.sh (cron */5, threshold 80°C) triggered graceful
    shutdown: `/sbin/shutdown -h +1`
  - VM 1020 backup failed: "interrupted by signal"
  - All VMs shut down in order, system halted. Did not auto-restart.
  - Root cause: thermal script threshold too aggressive for backup I/O load
  - Full investigation: TS-PVE-018
  - IO delay during backup: ~11% — NO master node impact, zero pod restarts,
    zero CrashLoopBackOff. Prod hardware handles backup I/O fine.

  DEV (pve-dev):
  - Backup completed fully but with K8s control plane degradation
  - kube-controller-manager and kube-scheduler entered CrashLoopBackOff on
    master2 and master3 for ~10 minutes during backup window
  - IO delay during backup: 33-38% sustained for 13 minutes
  - CPU rose from avg 8% to 16%
  - Degradation auto-recovered once backup completed
  - Apps and services stayed available throughout

What this tells me:
  Two separate issues with different root causes:

  1. Prod shutdown was caused by temperature_monitor.sh, NOT NAS overwhelm.
     The script's 80°C threshold is too low for vzdump+zstd load which
     routinely spikes to 85-92°C on laptop hardware. Reproduced and confirmed.

  2. Dev master degradation is caused by weak dev hardware under backup I/O.
     IO delay of 33-38% overwhelms the dev laptop, causing kubectl delays
     (~3s) and control plane liveness probe failures. Prod at only 11% IO
     delay had zero cluster impact — confirming this is a hardware capacity
     issue, NOT a NAS saturation or schedule overlap problem.

  The original suspicion (NAS overwhelm from concurrent backup) was wrong.
  NAS handles concurrent writes fine — it's a dedicated storage appliance
  with dedicated switch ports. The USB3-to-eth adapters carry limited
  bandwidth anyway. Both failures are hardware-specific to each laptop.

_____________________________________________________________________

[Findings — Updated 2026-04-23]

1. vzdump snapshot-mode backup completes in ~10 minutes for the full
   environment (9 VMs + 7 LXCs). Non-disruptive to application-layer
   workloads (WordPress, MariaDB stay responsive, zero pod restarts).

2. Worker VMs are the largest backups (6+ GB) due to container runtime
   data. LXCs are small (< 1.2G). Total footprint ~30-35GB per host.

3. Golden images (shutdown templates) back up fine — they're just disk
   snapshots. No special handling needed.

4. vzdump + zstd compression causes CPU thermal spikes on laptop hardware
   (idle 65°C → peak 92°C). The temperature_monitor.sh script with 80°C
   threshold will trigger shutdown on every backup run. Threshold must be
   raised or backup-awareness added to the script (TS-PVE-018).

5. K8s control plane impact is hardware-dependent, NOT backup-inherent:
   - Prod (stronger laptop): 11% IO delay, zero master impact, zero
     CrashLoopBackOff, zero pod restarts
   - Dev (weaker laptop): 33-38% IO delay for 13 minutes, causes
     kube-controller-manager and kube-scheduler CrashLoopBackOff on 2
     masters for ~10 minutes. HA mitigates — apps stay available.
   The original Test 1.2 conclusion ("safe for production hours") holds
   for prod hardware but not for dev.

6. Correction: NAS is NOT overwhelmed by concurrent backup from both hosts.
   The prod shutdown was caused by thermal script, not NAS saturation.
   Staggering schedules is still good practice but not critical.

_____________________________________________________________________

[References]

- TS-PVE-015 — mid-backup crash incident (dev) — likely same thermal root cause, no script = hard crash
- TS-PVE-018 — prod graceful thermal shutdown during backup — root cause confirmed
- nas-dev-data:/dump/ — dev backup storage
- nas-prod-data:/dump/ — prod backup storage
