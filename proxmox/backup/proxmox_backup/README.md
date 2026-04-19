# Proxmox Config Backup

Host-config tarball backup — the complement to vzdump workload backups. Runs
from cron on each Proxmox host and drops a timestamped tarball to the NAS,
keeping the last 5.

For the rationale (why this script + why no PBS), see [`../DESIGN.md`](../DESIGN.md).
For the install + disaster-recovery restore path, see the full-host recovery
runbook at [`../../disaster_recovery/recovery/`](../../disaster_recovery/recovery/).

## Files

| File | Purpose |
|------|---------|
| `backup-proxmox-config.sh` | The backup script (runs from cron, tars /etc/pve + essentials to the NAS) |

## What gets tar'd

The script captures everything needed to rebuild a Proxmox host on replacement
hardware:

- `/etc/pve` (cluster config, storage, users)
- `/etc/network/interfaces`
- `/etc/fstab`
- `/etc/ssh/sshd_config` + root authorized_keys
- GRUB + modprobe + sysctl configs
- Cron, systemd units
- `SYSTEM-INFO.txt` snapshot (cpu, memory, OS, disk layout — for reference during restore)

## Retention

Last 5 tarballs per host. Older ones auto-pruned by the script. Managed
alongside the NAS backup storage in
`terraform/<env>/proxmox/storage/nas/variables.tf`.

## Related

- [`../README.md`](../README.md) — backup folder scope
- [`../DESIGN.md`](../DESIGN.md) — why config backup + vzdump combined (instead of PBS)
- [`../../disaster_recovery/recovery/full-recovery-guide.txt`](../../disaster_recovery/recovery/full-recovery-guide.txt) — the restore runbook that consumes these tarballs
