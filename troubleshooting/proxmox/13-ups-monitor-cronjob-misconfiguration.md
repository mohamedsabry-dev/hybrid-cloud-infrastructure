# TS-PVE-013 | 2026-04-09 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Proxmox VE / UPS Monitoring / Cron
Sub-techs: NUT UPS monitor, dr_ups_monitor.sh script
Environment: PROD (pve-prod)
Re-opened: No

_____________________________________________________________________

[Issue Description]
REAL INCIDENT -- occurred during unplanned power outage, not planned DR testing.

UPS monitor script did not trigger automatic shutdown on prod during a power outage. I had to run the script manually at 41% battery instead of it running automatically at the 55% threshold.

Dev server (correct):
```bash
root@pve-dev:~# crontab -l
*/5 * * * * /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1
0 21 * * 4,6 /root/scripts/backup-proxmox-config.sh >> /var/log/backup-proxmox-config.log
```

Prod server (incorrect):
```bash
root@pve-prod:~# crontab -l
0 21 * * 4,6 /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1
0 4 * * 0 /root/scripts/backup-proxmox-config.sh >> /var/log/backup-proxmox-config.log
```

_____________________________________________________________________

[Analysis]
# Step 1: Compare crontab entries
```bash
# Dev - UPS runs every 5 minutes
*/5 * * * * /root/scripts/dr_ups_monitor.sh

# Prod - UPS runs only at 21:00 on Thu/Sat (wrong!)
0 21 * * 4,6 /root/scripts/dr_ups_monitor.sh
```
Prod crontab has wrong schedule -- UPS monitor only runs twice per week at 21:00 instead of every 5 minutes.

# Step 2: Verify script not running during outage
```bash
root@pve-prod:~# ps | grep ups
root@pve-prod:~#
```
No UPS monitor process running on prod during outage.

# Step 3: Timeline
- Power outage occurred
- Dev server: script detected battery at 55%, triggered graceful shutdown automatically
- Prod server: script never ran (wrong cron schedule)
- I ran the script manually at 41% battery
- Script triggered shutdown at 41%
- Electricity recovered after 3 hours

_____________________________________________________________________

[Final Root Cause]
Copy-paste error during initial setup. The crontab entries for UPS monitor and backup script were swapped on prod server. UPS monitor was given the weekly backup schedule instead of the 5-minute interval.

_____________________________________________________________________

[Final Solution]
Updated prod crontab to match dev configuration.

```bash
crontab -e
# Change from:
0 21 * * 4,6 /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1

# To:
*/5 * * * * /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1
```

Verification:
```bash
root@pve-prod:~# crontab -l | grep ups
*/5 * * * * /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1
```

To catch this in the future:
```bash
diff <(ssh pve-dev crontab -l) <(ssh pve-prod crontab -l)
```

Verified: Yes -- UPS monitor now runs every 5 minutes on both dev and prod.

_____________________________________________________________________

[Risk Level] LOW

_____________________________________________________________________

[References]
- Related: TS-PVE-012 (VM Autostart Timeout NFS Disk Not Ready) -- also encountered during this incident
