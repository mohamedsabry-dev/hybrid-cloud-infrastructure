# TS-PVE-005 | 2026-03-20 | RESOLVED

## 1. Context
- System: Proxmox VE backup jobs (vzdump)
- Environment: DEV (pve-dev) - laptop-based Proxmox node
- Related components: /etc/pve/jobs.cfg, vzdump scheduler

## 2. Issue
- Symptom: DEV Proxmox backups were not running when expected. Last backup was March 15, but expected March 19 (Thursday)
- Error: No error - backup job simply did not run

**Observed Behavior:**
```
DEV:  Last backup March 15 — missed March 19 (Thursday)
PROD: Last backup March 20 — ran successfully after laptop came online
```

Both laptops were closed (offline) during scheduled backup time (Thursday 21:00).
PROD ran backup when it came online Friday. DEV did not.

## 3. Analysis

**Check backup job configuration:**

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

**What `repeat-missed` Does:**

| Setting | Behavior |
|---------|----------|
| `repeat-missed 0` (default) | If node offline during schedule, backup is skipped |
| `repeat-missed 1` | If node offline during schedule, backup runs when node comes online |

## 4. Root Cause
> DEV backup job missing `repeat-missed` flag. When the laptop was offline during scheduled backup time, the backup was simply skipped rather than run when the node came back online.

## 5. Solution
> Enable `repeat-missed` flag on DEV backup job.

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

## 6. Solution Risk
- Risk level: LOW
- Potential impact: Backup may run immediately when node comes online, causing brief load

## 7. Impact After Fix
- Observed: Missed backups now run when node comes online
- DEV and PROD backup configurations consistent
- No more silent backup failures

**Impact from missed backups:**
- Lost 5 days of backups on DEV (March 15 → March 20)
- Had to restore from older backup when vault LXCs needed recovery
- Manual work lost between backups

## 8. Notes

**Prevention:**
1. **Always enable `repeat-missed`** on laptop-based Proxmox nodes
2. **Document backup config** in `proxmox/backup/backup_config_guide.txt`
3. **Monitor backup job status** via email notifications
4. **Compare DEV/PROD configs** periodically for consistency

## 9. Workaround (if any)
> Manually trigger backup via GUI or CLI when node comes online: `vzdump --all --storage nas-dev-data`

## Related Files
- `/etc/pve/jobs.cfg` - Proxmox backup job configuration
- `proxmox/backup/backup_config_guide.txt` - Documented backup settings
