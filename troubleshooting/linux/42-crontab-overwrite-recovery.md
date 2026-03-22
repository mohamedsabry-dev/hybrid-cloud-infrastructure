# Troubleshooting: Crontab Accidentally Overwritten - Recovery via Backup

**Date:** 2026-03-22
**Environment:** pve-dev (Proxmox)
**Category:** Linux / Cron

---

## Problem Statement

After adding a new cron job using `echo "..." | crontab -`, all existing cron jobs disappeared. Only the newly added job remained.

**Before:**
```
*/5 * * * * /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1
```

**After (wrong command):**
```
0 4 * * 0 /root/scripts/backup-proxmox-config.sh
```

The UPS monitor cron job was lost.

---

## Root Cause

**Using `echo ... | crontab -` REPLACES the entire crontab instead of appending.**

| Command | Behavior |
|---------|----------|
| `echo "job" \| crontab -` | **REPLACES** all cron jobs with just "job" |
| `(crontab -l; echo "job") \| crontab -` | **APPENDS** "job" to existing cron jobs |

The `-` in `crontab -` means "read from stdin", which replaces the entire crontab file.

---

## Recovery Process

### Step 1: Check if backup exists

The `backup-proxmox-config.sh` script backs up crontab to NAS. Check for recent backups:

```bash
ls -lt /mnt/pve/nas-backups/dump/proxmox-config-*.tar.gz | head -5
```

### Step 2: Extract and find old crontab

```bash
# Extract latest backup
tar -xzf /mnt/pve/nas-backups/dump/proxmox-config-pve-dev-20260321-114253.tar.gz -C /tmp

# View the backed up crontab
cat /tmp/proxmox-config-pve-dev-20260321-114253/cron/root-crontab.txt
```

**Output:**
```
*/5 * * * * /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1
```

### Step 3: Restore all cron jobs

```bash
crontab -e
# Add these lines:
*/5 * * * * /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1
0 21 * * 4,6 /root/scripts/backup-proxmox-config.sh >> /var/log/backup-proxmox-config.log 2>&1
```

### Step 4: Verify

```bash
crontab -l
```

**Output:**
```
*/5 * * * * /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1
0 21 * * 4,6 /root/scripts/backup-proxmox-config.sh >> /var/log/backup-proxmox-config.log 2>&1
```

**Schedule:**
- UPS monitor: Every 5 minutes (continuous power monitoring)
- Config backup: Thursday & Saturday 9 PM (before/after weekend work, when env is up)

---

## Prevention

### Correct Way to Add Cron Jobs

**ALWAYS append, never replace:**

```bash
# CORRECT - Appends to existing cron
(crontab -l 2>/dev/null; echo "0 4 * * 0 /root/scripts/backup.sh") | crontab -

# WRONG - Replaces entire crontab!
echo "0 4 * * 0 /root/scripts/backup.sh" | crontab -
```

The `2>/dev/null` suppresses "no crontab for user" error on first use.

### Alternative: Edit Directly

```bash
crontab -e
```

Opens crontab in editor - safer for manual additions.

---

## Lessons Learned

1. **`crontab -` replaces, not appends** - Always use the `(crontab -l; echo ...) | crontab -` pattern
2. **Backup scripts save the day** - The `backup-proxmox-config.sh` script captured crontab, enabling recovery
3. **Document cron jobs** - Keep a record of expected cron jobs in documentation

---

## Files Updated

- `proxmox/backup-proxmox-config.sh` - Added warning about crontab replacement
- `proxmox/disaster_recovery/dr_ups_setup.txt` - Added warning about crontab replacement

---

## Quick Reference

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

## Expected Cron Jobs on Proxmox Hosts

```bash
# UPS monitor - every 5 min (continuous power monitoring)
*/5 * * * * /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1

# Config backup - Thu & Sat 9 PM (before/after weekend work, when env is up)
0 21 * * 4,6 /root/scripts/backup-proxmox-config.sh >> /var/log/backup-proxmox-config.log 2>&1
```
