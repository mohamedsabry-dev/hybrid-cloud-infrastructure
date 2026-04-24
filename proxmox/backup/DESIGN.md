# Backup layer — design notes and reasoning

Why backup is split into two small pieces (Proxmox config backup + workload vzdump) instead of running Proxmox Backup Server, and how the frequency and retention policies got to where they are today. Reads as a narrative — for the concrete scripts, jobs, and performance numbers, see [`proxmox_backup/`](proxmox_backup/) and [`workload_backup/`](workload_backup/).

---

## Why I'm not running Proxmox Backup Server (PBS)

PBS is the "proper" answer for a Proxmox fleet — a dedicated backup server with deduplication, incremental chains, pruning, and verification. I looked at it, and I'm deliberately NOT running it. Three reasons:

1. **Overhead and resource consumption.** PBS is another service to install, another system to maintain, another box's worth of RAM/CPU to reserve. My fleet is two laptops plus a NAS; adding a third role for "backup server" is a lot of surface area for a project whose focus is something else entirely.

2. **Chicken-and-egg problem.** A dedicated backup server needs its own backup strategy — otherwise one of my backup targets is itself unprotected. That spirals. "Who backs up the backup server" is the kind of question I didn't want to answer at this phase.

3. **Out of scope.** The point of this project is Kubernetes on hybrid cloud — IAM, GitOps, k8s, Vault integration, networking. Running a PBS deployment pulls scope away from what I'm actually trying to demonstrate. PBS would be the right call for a fleet of 50 Proxmox hosts. For a fleet of 2, it's pure ceremony.

What I chose instead is a split that covers the same failure modes with less footprint.

## What I actually backup, and how

### 1. Proxmox host config (script-based)

`proxmox_backup/backup-proxmox-config.sh` is a config-copy script I built with AI help, based on the set of files I'd actually need to restore a Proxmox host from bare metal: `/etc/pve`, `/etc/network/interfaces`, `/etc/fstab`, `/etc/ssh/sshd_config`, grub, modprobe, cron, systemd units, SYSTEM-INFO snapshot, and so on. Produces a timestamped tarball, drops it on the NAS via the `nas-backups` NFS mount, rotates to keep the last 5 per host.

It deliberately does NOT cover VM/LXC data — that's `vzdump`'s job (below).

**Why this is enough for me:** the disaster scenario I'm covering is "Proxmox host disk damaged beyond repair, reinstall from scratch." The recovery path is:

1. Fresh Proxmox VE install on replacement hardware.
2. Run [`../bootstrap_proxmox/bootstrap.sh`](../bootstrap_proxmox/bootstrap.sh) + [`../bootstrap_proxmox/network-setup.sh`](../bootstrap_proxmox/network-setup.sh) (+ `mail-config.sh` if needed) — Proxmox host back to the baseline.
3. Mount the NAS, pull the latest config tarball, apply it — Proxmox host back to the *exact* prior state (VM definitions, storage, network bridges, cron, all of it).
4. Restore workloads from the NAS vzdump archives (below).
5. Rotate the Proxmox API tokens — update them in AWS Secrets Manager (`{env}/proxmox/terraform-token`) and in Vault where relevant.

That full path is less than a day on a known-good replacement. PBS wouldn't be materially faster — the rebuild time is dominated by reinstall + vzdump restore, not by whatever backup format we used.

### 2. Workload backups (vzdump → NAS NFS)

Each Proxmox host runs a vzdump job (`all 1, mode=snapshot, compress=zstd, repeat-missed=1`) targeting the NAS via NFS. Details in [`workload_backup/backup-snapshot.md`](workload_backup/backup-snapshot.md) and [`workload_backup/backup_config_guide.txt`](workload_backup/backup_config_guide.txt).

The `repeat-missed = 1` setting matters specifically because the Proxmox hosts are laptops — they are not guaranteed to be awake at the scheduled time. Without `repeat-missed`, a missed window = a lost backup.

---

## Frequency: 2/week → 3-4/week (planned change)

**Original schedule:** Thursday and Saturday at 21:00 — two backups per week, timed around weekend work (pre-change Thursday, post-change Saturday).

**Why I'm planning to move to 3-4/week distributed every 2 days:** I ran the performance test documented in [`workload_backup/test-performance-plan.md`](workload_backup/test-performance-plan.md). The observation was that **the env doesn't notice the backup.** K8s workloads keep running smoothly through the backup window, Vault stays up and responsive, the network doesn't saturate. The initial 2/week cadence was cautious — picked before I had the numbers — and now that I have the numbers, there's no reason to stay at 2.

**Planned cadence:** every 2 days, so roughly 3-4 per week depending on the month. Evenly distributed instead of lumped around the weekend, which matches how my actual changes land (I edit throughout the week, not just Fri/Sat).

This change is scheduled in the Terraform + PVE job config; the scripts already handle higher-frequency runs correctly.

## Retention: 2 → 5 (already deployed)

**Started with `keep_last = 2`** — one Thursday, one Saturday, covering "before weekend changes" and "after weekend changes". Minimum footprint, nice diagram, felt sufficient.

**Moved to `keep_last = 5`** after the incident in [`../../troubleshooting/terraform/10-cloud-init-ssh-host-key-regeneration.md`](../../troubleshooting/terraform/10-cloud-init-ssh-host-key-regeneration.md), which taught me something uncomfortable about k8s + infra changes: **a change made on day 1 doesn't always show up as broken until day 3, 4, or 5.** With only 2 backups around, by the time the symptom surfaced, the pre-change state was already off the tape.

With 5 backups retained:

- If I hit an issue on day 5 that traces back to an edit on day 1, I can restore a dummy VM from that day and **diff the config side-by-side** with current state to find what actually changed.
- Or do a full restore to the last known-good state if diffing isn't enough.
- Either way, a 5-backup window gives me nearly a full week of history — long enough to catch the slow-burn k8s issues that don't manifest immediately.

NAS capacity is not the constraint here (plenty of space on the `FS6706T`). The real constraint is "how far back can I look when an issue turns out to be rooted deeper than I thought", and 5 is where that constraint stops biting.

This matches the `keep_last = 5` value already deployed in `terraform/*/proxmox/storage/nas/variables.tf` for both `nas_data` and `backups`.

---

## What is deliberately NOT here

- **No Proxmox Backup Server.** Reasoning above.
- **No off-site backup replication.** Current state: NAS is the single backup target. For a portfolio project that's acceptable; for a real production system it wouldn't be. Noted as a gap, not a design choice — if the NAS dies I lose both envs' last-known-good.
- **No application-consistent backup coordination with Vault or k8s etcd.** vzdump at `mode=snapshot` gives filesystem-consistent VM state, not necessarily application-consistent for distributed systems. K8s etcd backups are handled separately by a k8s CronJob ([`../../kubernetes/`](../../kubernetes/)) that runs `etcdctl snapshot save`; that's the k8s-layer story, not this layer's.

---

## Related

- [`proxmox_backup/backup-proxmox-config.sh`](proxmox_backup/backup-proxmox-config.sh) — config backup script
- [`workload_backup/backup-snapshot.md`](workload_backup/backup-snapshot.md) — vzdump schedule, modes, retention, snapshot notes
- [`workload_backup/backup_config_guide.txt`](workload_backup/backup_config_guide.txt) — PVE backup job config reference
- [`workload_backup/test-performance-plan.md`](workload_backup/test-performance-plan.md) — the performance testing that drove the 2/week → 3-4/week change
- [`../../troubleshooting/terraform/10-cloud-init-ssh-host-key-regeneration.md`](../../troubleshooting/terraform/10-cloud-init-ssh-host-key-regeneration.md) — the incident that drove retention 2 → 5
