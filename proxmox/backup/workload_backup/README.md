# Workload Backup — Reference Docs

Documentation for the Proxmox-native vzdump job that backs up VMs and LXCs
to the NAS. Reference / tuning material, not a setup runbook — the job
itself is configured once in the PVE web UI and then runs on schedule.

For the backup strategy rationale (why no PBS, retention 2 → 5, schedule
evolution), see [`../DESIGN.md`](../DESIGN.md).

## Files

| File | Purpose |
|------|---------|
| `backup-snapshot.md` | Main reference: schedule, modes, retention policy, snapshot semantics |
| `backup_config_guide.txt` | `/etc/pve/jobs.cfg` layout + PVE web-UI config walkthrough |
| `test-performance-plan.md` | Performance test plan for the 2/week → 3-4/week schedule decision |
| `backup-performance-test-explained.txt` | Performance test results + commentary |

## Related

- [`../README.md`](../README.md) — backup folder scope
- [`../DESIGN.md`](../DESIGN.md) — why vzdump (not PBS), retention rationale
- [`../proxmox_backup/backup-proxmox-config.sh`](../proxmox_backup/backup-proxmox-config.sh) — the OTHER half of the backup story (host-config tarball)
