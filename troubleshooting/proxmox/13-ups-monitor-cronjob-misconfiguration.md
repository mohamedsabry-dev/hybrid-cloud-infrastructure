# TS-PVE-013 | 2026-04-09 | RESOLVED

## 1. Context
- System: Proxmox VE / UPS Monitoring / Cron
- Environment: PROD (pve-prod)
- Related components: NUT UPS monitor, dr_ups_monitor.sh script
- Discovered during: Real power outage incident (unplanned)

## 2. Issue
- Symptom: UPS monitor script did not trigger automatic shutdown on prod during power outage
- Error: Script ran manually at 41% battery instead of automatically at 55% threshold
- Impact: Risk of unclean shutdown if battery depleted before manual intervention

**Observation:**

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

## 3. Analysis

**Check 1: Compare Crontab Entries**
```bash
# Dev - UPS runs every 5 minutes
*/5 * * * * /root/scripts/dr_ups_monitor.sh

# Prod - UPS runs only at 21:00 on Thu/Sat (wrong!)
0 21 * * 4,6 /root/scripts/dr_ups_monitor.sh
```
Finding: Prod crontab has wrong schedule - UPS monitor only runs twice per week at 21:00 instead of every 5 minutes.

---

**Check 2: Verify Script Not Running**
```bash
root@pve-prod:~# ps | grep ups
root@pve-prod:~#
```
Finding: No UPS monitor process running on prod during outage.

---

**Check 3: Timeline**
```
- Power outage occurred
- Dev server: Script detected battery at 55%, triggered graceful shutdown automatically
- Prod server: Script never ran (wrong cron schedule)
- Manual intervention: Ran script manually at 41% battery
- Script triggered shutdown at 41%
- Electricity recovered after 3 hours
```

## 4. Root Cause
> Copy-paste error during initial setup. The crontab entries for UPS monitor and backup script were swapped on prod server. UPS monitor was given the weekly backup schedule instead of the 5-minute interval.

## 5. Solution
> Update prod crontab to match dev configuration.

**Fix:**
```bash
crontab -e
# Change from:
0 21 * * 4,6 /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1

# To:
*/5 * * * * /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1
```

**Verification:**
```bash
root@pve-prod:~# crontab -l | grep ups
*/5 * * * * /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact: None - only affects monitoring frequency

## 7. Impact After Fix
- UPS monitor now runs every 5 minutes on both dev and prod
- Automatic shutdown will trigger at 55% battery threshold

## 8. Notes

**Prevention:**
- Always diff crontabs between dev and prod after setup
- Use Ansible to manage crontabs for consistency
- Add monitoring alert for UPS script not running

**Verification Command:**
```bash
# Compare dev and prod crontabs
diff <(ssh pve-dev crontab -l) <(ssh pve-prod crontab -l)
```

**Related:**
- TS-PVE-012: VM Autostart Timeout NFS Disk Not Ready (also encountered during this incident)

## 9. Workaround (if any)
> Manual script execution: `/root/scripts/dr_ups_monitor.sh`
