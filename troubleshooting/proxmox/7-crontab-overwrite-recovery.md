# TS-PVE-007 | 2026-03-22 | RESOLVED

## 1. Context
- System: Proxmox / Cron
- Environment: pve-dev (Proxmox host)
- Related components: Crontab, backup scripts, UPS monitor

## 2. Issue
- Symptom: After adding a new cron job, all existing cron jobs disappeared
- Error: No error - silent data loss

**Before (existing crontab):**
```
*/5 * * * * /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1
```

**Command used (WRONG):**
```bash
echo "0 4 * * 0 /root/scripts/backup-proxmox-config.sh" | crontab -
```

**After (entire crontab replaced):**
```
0 4 * * 0 /root/scripts/backup-proxmox-config.sh
```

The UPS monitor cron job was lost.

## 3. Analysis

**Check 1: What does `crontab -` do?**
```bash
man crontab
# -    read crontab from standard input
```
Finding: `crontab -` reads from stdin and **REPLACES** the entire crontab.

**Check 2: Compare commands**

| Command | Behavior |
|---------|----------|
| `echo "job" \| crontab -` | **REPLACES** all cron jobs with just "job" |
| `(crontab -l; echo "job") \| crontab -` | **APPENDS** "job" to existing cron jobs |

Finding: The `-` means "read entire crontab from stdin" - it's a replacement, not append.

**Check 3: Is there a backup?**
```bash
ls -lt /mnt/pve/nas-backups/dump/proxmox-config-*.tar.gz | head -5
```
Finding: Yes - the `backup-proxmox-config.sh` script backs up crontab to NAS.

## 4. Root Cause
> Using `echo ... | crontab -` **REPLACES** the entire crontab instead of appending. The `-` in `crontab -` means "read from stdin", which completely overwrites the existing crontab file.

## 5. Solution
> Recover from backup and use correct append syntax going forward.

**Step 1: Extract and find old crontab from backup**
```bash
# Extract latest backup
tar -xzf /mnt/pve/nas-backups/dump/proxmox-config-pve-dev-20260321-114253.tar.gz -C /tmp

# View the backed up crontab
cat /tmp/proxmox-config-pve-dev-20260321-114253/cron/root-crontab.txt
```
```
*/5 * * * * /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1
```

**Step 2: Restore all cron jobs**
```bash
crontab -e
# Add these lines:
*/5 * * * * /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1
0 21 * * 4,6 /root/scripts/backup-proxmox-config.sh >> /var/log/backup-proxmox-config.log 2>&1
```

**Step 3: Verify**
```bash
crontab -l
```
```
*/5 * * * * /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1
0 21 * * 4,6 /root/scripts/backup-proxmox-config.sh >> /var/log/backup-proxmox-config.log 2>&1
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact: None - just restoring and using correct syntax

## 7. Impact After Fix
- Observed: Both cron jobs running correctly
- UPS monitor: Every 5 minutes (continuous power monitoring)
- Config backup: Thursday & Saturday 9 PM (before/after weekend work)

## 8. Notes

**Correct way to add cron jobs:**

```bash
# CORRECT - Appends to existing cron
(crontab -l 2>/dev/null; echo "0 4 * * 0 /root/scripts/backup.sh") | crontab -

# WRONG - Replaces entire crontab!
echo "0 4 * * 0 /root/scripts/backup.sh" | crontab -
```

The `2>/dev/null` suppresses "no crontab for user" error on first use.

**Alternative - edit directly (safer for manual additions):**
```bash
crontab -e
```

**Quick reference:**
```bash
# List current cron jobs
crontab -l

# Edit interactively (RECOMMENDED - safe)
crontab -e

# Backup crontab
crontab -l > ~/crontab-backup.txt

# Restore from backup
crontab ~/crontab-backup.txt
```

**Expected cron jobs on Proxmox hosts:**
```bash
# UPS monitor - every 5 min (continuous power monitoring)
*/5 * * * * /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1

# Config backup - Thu & Sat 9 PM (before/after weekend work, when env is up)
0 21 * * 4,6 /root/scripts/backup-proxmox-config.sh >> /var/log/backup-proxmox-config.log 2>&1
```

**Lessons learned:**
1. `crontab -` replaces, not appends - always use `(crontab -l; echo ...) | crontab -`
2. Backup scripts save the day - the backup captured crontab enabling recovery
3. Document cron jobs - keep expected cron jobs in documentation

## 9. Workaround (if any)
> If no backup exists, manually recreate cron jobs from memory/documentation.

## Related Files
- `proxmox/backup-proxmox-config.sh` - Added warning about crontab replacement
- `proxmox/disaster_recovery/dr_ups_setup.txt` - Added warning about crontab replacement
