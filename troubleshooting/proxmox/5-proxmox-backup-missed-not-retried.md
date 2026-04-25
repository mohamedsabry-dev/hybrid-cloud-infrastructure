# TS-PVE-005 | 2026-03-20 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Proxmox VE / Backup
Sub-techs: vzdump scheduler, jobs.cfg, repeat-missed flag
Environment: DEV (pve-dev) — laptop-based Proxmox node
Re-opened: No

_____________________________________________________________________

[Issue Description]
DEV Proxmox backups weren't running when expected. Last backup was March 15, but
expected March 19 (Thursday). Both laptops were closed (offline) during scheduled
backup time (Thursday 21:00). PROD ran backup when it came online Friday. DEV did
not.

```
DEV:  Last backup March 15 — missed March 19 (Thursday)
PROD: Last backup March 20 — ran successfully after laptop came online
```

_____________________________________________________________________

[Analysis]

Compared backup job configs:

```bash
# DEV - missing repeat-missed
root@pve-dev:~# cat /etc/pve/jobs.cfg
vzdump: backup-769f8091-c41c
        schedule thu,sat 21:00
        all 1
        storage nas-dev-data
        # NO repeat-missed setting!

# PROD - has repeat-missed enabled
root@pve-prod:~# cat /etc/pve/jobs.cfg
vzdump: backup-23446773-fa34
        schedule thu,sat 21:00
        all 1
        storage nas-prod-data
        repeat-missed 1
```

`repeat-missed 0` (default): if node offline during schedule, backup is skipped.
`repeat-missed 1`: if node offline during schedule, backup runs when node comes
online.

_____________________________________________________________________

[Final Root Cause]
DEV backup job missing `repeat-missed` flag. When the laptop was offline during
scheduled backup time, the backup was simply skipped rather than run when the
node came back online.

_____________________________________________________________________

[Final Solution]

```bash
pvesh set /cluster/backup/backup-769f8091-c41c --repeat-missed 1

# Verify
cat /etc/pve/jobs.cfg | grep repeat-missed
# Should show: repeat-missed 1
```

Or via Web UI: Datacenter → Backup → Edit backup job → Check "Repeat missed"

Impact from missed backups: lost 5 days of backups on DEV (March 15 → March 20).
Had to restore from older backup when vault LXCs needed recovery.

Verified: Yes — missed backups now run when node comes online, DEV and PROD
configs consistent.

_____________________________________________________________________

[Risk Level] LOW

Backup may run immediately when node comes online, causing brief load.

_____________________________________________________________________

[References]
- /etc/pve/jobs.cfg — Proxmox backup job configuration
- TS-PVE-006 — mount point backup exclusion (discovered during same audit)
