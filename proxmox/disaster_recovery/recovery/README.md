# Full-Host Recovery

Runbook for complete Proxmox reinstall on replacement hardware and restoration
from the config-tarball + vzdump backups on the NAS. Use when a host fails
beyond in-place repair.

## Files

| File | Purpose |
|------|---------|
| `full-recovery-guide.txt` | 7-step runbook: fresh install → bootstrap → config restore → network → storage → workload restore → verify |

## When to use

- Complete hardware failure requiring new machine
- Corrupted Proxmox installation
- Disk failure requiring full reinstall

## Prerequisites

Backups must already exist BEFORE disaster. The runbook assumes you have:

- Config tarball from `../../backup/proxmox_backup/backup-proxmox-config.sh` on the NAS
- VM / LXC vzdump backups on the NAS
- Proxmox ISO on a USB drive
- Network documentation accessible offline

## Related

- [`full-recovery-guide.txt`](full-recovery-guide.txt) — the actual runbook commands
- [`../README.md`](../README.md) — parent DR scope
- [`../../backup/`](../../backup/) — backup strategy (the thing this runbook consumes)
- [`../../bootstrap_proxmox/`](../../bootstrap_proxmox/) — bootstrap + network-setup scripts used during recovery
