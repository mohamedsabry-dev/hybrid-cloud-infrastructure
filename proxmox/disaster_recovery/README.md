# Proxmox Disaster Recovery

Host-layer operational runbooks and prevention scripts for the Proxmox hypervisors. Specific to failures at the laptop / hardware / electricity / thermal / reinstall level — the foundation everything else sits on.

> **Design notes & reasoning** — for the scope boundary between this folder and the repo-level [`/disaster-recovery/`](../../disaster-recovery/) (platform-wide chaos test plans + results), and why each subfolder is here, see [`DESIGN.md`](DESIGN.md).

---

## Subfolders

| Folder | Scenario | What it contains |
|--------|----------|------------------|
| [`power/`](power/) | Power / battery loss | UPS (laptop battery) monitor — graceful shutdown on sustained discharge |
| [`thermal/`](thermal/) | CPU temperature | Temperature monitor — vzdump-aware, shutdown after 5 min sustained 90°C |
| [`io-storm/`](io-storm/) | IO cascade | IO storm watchdog — detects source VM by CPU+IO fingerprint, auto-resets |
| [`hardware/`](hardware/) | Hardware failure | Runbook for USB-Ethernet adapter replacement (MAC mapping, safe order) |
| [`recovery/`](recovery/) | Full host rebuild | Runbook for reinstalling Proxmox from scratch + restoring config + VMs |

## Prevention (what's already running)

| Item | Location | Purpose |
|------|----------|---------|
| Config backup | [`../backup/proxmox_backup/backup-proxmox-config.sh`](../backup/proxmox_backup/backup-proxmox-config.sh) | Tarball of `/etc/pve` + essentials, pushed to NAS |
| VM / LXC backups | Proxmox `vzdump` job | Scheduled backups to NAS — see [`../backup/`](../backup/) |
| Spare adapters | Physical | Keep spare USB-Ethernet adapters ready |
| UPS monitor | [`power/dr_ups_monitor.sh`](power/dr_ups_monitor.sh) | Auto graceful shutdown on battery discharge |
| Temperature monitor | [`thermal/temperature_monitor.sh`](thermal/temperature_monitor.sh) | Daemon — vzdump-aware, 5-min sustained threshold before shutdown |
| IO storm watchdog | [`io-storm/io-storm-watchdog.sh`](io-storm/io-storm-watchdog.sh) | Daemon — detects IO cascade source VM, auto-resets it |

## Not here

Platform-wide chaos test plans and results (k8s, Vault, etcd, NFS, Nginx, IPA, etc.) live in [`/disaster-recovery/`](../../disaster-recovery/). See [`DESIGN.md`](DESIGN.md) for the exact boundary.
