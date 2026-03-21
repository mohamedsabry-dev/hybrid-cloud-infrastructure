# TS-037: Proxmox Backup Not Retrying After Missed Schedule

**Date:** 2026-03-20
**Environment:** DEV (pve-dev)
**Affected Systems:** All DEV VMs/LXCs
**Status:** RESOLVED

---

## Symptom

DEV Proxmox backups were not running when expected. Last backup was March 15, but expected March 19 (Thursday).

### Observed Behavior

```
DEV:  Last backup March 15 — missed March 19 (Thursday)
PROD: Last backup March 20 — ran successfully after laptop came online
```

Both laptops were closed (offline) during scheduled backup time (Thursday 21:00).
PROD ran backup when it came online Friday. DEV did not.

---

## Root Cause

**DEV backup job missing `repeat-missed` flag.**

```bash
# DEV - missing repeat-missed (defaults to 0/false)
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
        repeat-missed 1          # ← This is the difference
```

### What `repeat-missed` Does

| Setting | Behavior |
|---------|----------|
| `repeat-missed 0` (default) | If node offline during schedule, backup is skipped |
| `repeat-missed 1` | If node offline during schedule, backup runs when node comes online |

---

## Resolution

### Fix via CLI

```bash
# On pve-dev
pvesh set /cluster/backup/backup-769f8091-c41c --repeat-missed 1
```

### Fix via Web UI

```
Datacenter → Backup → Edit backup job → Check "Repeat missed"
```

### Verify Fix

```bash
cat /etc/pve/jobs.cfg | grep repeat-missed
# Should show: repeat-missed 1
```

---

## Impact

- Lost 5 days of backups on DEV (March 15 → March 20)
- Had to restore from older backup when vault LXCs needed recovery
- Manual work lost between backups

---

## Prevention

1. **Always enable `repeat-missed`** on laptop-based Proxmox nodes
2. **Document backup config** in `proxmox/backup/backup_config_guide.txt`
3. **Monitor backup job status** via email notifications
4. **Compare DEV/PROD configs** periodically for consistency

---

## Related Files

- `/etc/pve/jobs.cfg` - Proxmox backup job configuration
- `proxmox/backup/backup_config_guide.txt` - Documented backup settings
