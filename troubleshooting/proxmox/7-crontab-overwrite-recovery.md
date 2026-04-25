# TS-PVE-007 | 2026-03-22 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Proxmox / Cron
Sub-techs: Crontab, backup scripts, UPS monitor
Environment: pve-dev (Proxmox host)
Re-opened: No

_____________________________________________________________________

[Issue Description]
After adding a new cron job, all existing cron jobs disappeared. Silent data loss -- no error message.

Before (existing crontab):
```
*/5 * * * * /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1
```

Command I used (WRONG):
```bash
echo "0 4 * * 0 /root/scripts/backup-proxmox-config.sh" | crontab -
```

After (entire crontab replaced):
```
0 4 * * 0 /root/scripts/backup-proxmox-config.sh
```

The UPS monitor cron job was lost.

_____________________________________________________________________

[Analysis]
# Step 1: What does `crontab -` do?
```bash
man crontab
# -    read crontab from standard input
```
`crontab -` reads from stdin and REPLACES the entire crontab.

# Step 2: Compare commands

| Command | Behavior |
|---------|----------|
| `echo "job" \| crontab -` | REPLACES all cron jobs with just "job" |
| `(crontab -l; echo "job") \| crontab -` | APPENDS "job" to existing cron jobs |

The `-` means "read entire crontab from stdin" -- it's a replacement, not append.

# Step 3: Check for backup
```bash
ls -lt /mnt/pve/nas-backups/dump/proxmox-config-*.tar.gz | head -5
```
Found one -- the `backup-proxmox-config.sh` script backs up crontab to NAS.

_____________________________________________________________________

[Final Root Cause]
Using `echo ... | crontab -` REPLACES the entire crontab instead of appending. The `-` in `crontab -` means "read from stdin", which completely overwrites the existing crontab file.

_____________________________________________________________________

[Final Solution]
Recovered from backup and restored all cron jobs.

Step 1: Extract old crontab from backup
```bash
tar -xzf /mnt/pve/nas-backups/dump/proxmox-config-pve-dev-20260321-114253.tar.gz -C /tmp
cat /tmp/proxmox-config-pve-dev-20260321-114253/cron/root-crontab.txt
```
```
*/5 * * * * /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1
```

Step 2: Restore all cron jobs
```bash
crontab -e
# Add these lines:
*/5 * * * * /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1
0 21 * * 4,6 /root/scripts/backup-proxmox-config.sh >> /var/log/backup-proxmox-config.log 2>&1
```

Step 3: Verify
```bash
crontab -l
```
```
*/5 * * * * /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1
0 21 * * 4,6 /root/scripts/backup-proxmox-config.sh >> /var/log/backup-proxmox-config.log 2>&1
```

Correct way to append cron jobs going forward:
```bash
# CORRECT - Appends to existing cron
(crontab -l 2>/dev/null; echo "0 4 * * 0 /root/scripts/backup.sh") | crontab -

# WRONG - Replaces entire crontab!
echo "0 4 * * 0 /root/scripts/backup.sh" | crontab -
```

Verified: Yes -- both cron jobs running correctly.

_____________________________________________________________________

[Risk Level] LOW

_____________________________________________________________________

[References]
- `proxmox/backup-proxmox-config.sh` -- added warning about crontab replacement
- `proxmox/disaster_recovery/dr_ups_setup.txt` -- added warning about crontab replacement
