# TS-PVE-023: Temperature Monitor Daemon Spawning as Cron Job — 132 Duplicate Processes

**Date:** 2026-05-31
**Status:** Resolved
**Host:** pve-prod
**Script:** temperature_monitor.sh → /root/scripts/temperature_monitor.sh

---

## Discovery

Found during technical papers review session — reviewing the watchdog scripts summary trace. Noticed the temperature_monitor.log only showed repeated "=== Temperature Monitor started ===" entries every 5 minutes with no temperature readings between them. Expected behavior: one "started" entry at boot, then temperature readings every 30s.

## Symptoms

- Log showed `=== Temperature Monitor started ===` every 5 minutes
- No temperature readings logged between start entries
- `ps aux | grep temperature` returned **132 duplicate processes** (264 total with sh wrappers)
- Each instance spawned every 5 minutes from 12:00 to 23:00

## Root Cause

Wrong cron schedule. temperature_monitor.sh is a **daemon** (infinite `while true` loop with `sleep 30`), but the crontab entry used `*/5 * * * *` (run every 5 minutes) instead of `@reboot` (run once at boot).

**Before (wrong):**
```
*/5 * * * * /root/scripts/temperature_monitor.sh >> /var/log/temperature_monitor.log 2>&1
```

Cron fired the script every 5 minutes. The script entered its infinite loop and never exited. 5 minutes later, cron fired another copy. Both running. Repeat indefinitely — accumulating ~12 zombie daemons per hour.

**Why no temperature readings in log:** The script only logs when temp >= 90°C or when it cools down after being hot. Normal readings below threshold are silent by design. So each instance was quietly checking temperature every 30s — 132 scripts all reading the same sensor file simultaneously.

## Risk

If temperature had hit 90°C sustained:
- 132 instances would each independently send a warning email
- 132 instances would each trigger `/sbin/shutdown -h +1`
- 132 critical emails flooding the inbox simultaneously

## Evidence

```
root@pve-prod:~# ps aux | grep temperature
root   2490  0.0  0.0  2684  1856 ?  Ss  12:00  0:00 /bin/sh -c /root/scripts/temperature_monitor.sh ...
root   2493  0.0  0.0  7092  3324 ?  S   12:00  0:00 /bin/bash /root/scripts/temperature_monitor.sh
root   4737  0.0  0.0  2684  1932 ?  Ss  12:05  0:00 /bin/sh -c /root/scripts/temperature_monitor.sh ...
root   4739  0.0  0.0  7092  3448 ?  S   12:05  0:00 /bin/bash /root/scripts/temperature_monitor.sh
... (132 pairs, every 5 min from 12:00 to 23:00)
```

Crontab before fix:
```
@reboot sleep 900 && /root/scripts/io-storm-watchdog.sh >> /var/log/io-storm-watchdog.log 2>&1 &
0 21 * * 4,6 /root/scripts/backup-proxmox-config.sh >> /var/log/backup-proxmox-config.log
*/5 * * * * /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1
*/5 * * * * /root/scripts/temperature_monitor.sh >> /var/log/temperature_monitor.log 2>&1   ← WRONG
```

Note: io-storm-watchdog.sh is the same pattern (daemon, infinite loop) and was correctly set to `@reboot`. Temperature monitor line was likely copy-pasted from the UPS monitor entry without changing the schedule.

## Fix

1. Changed crontab entry from `*/5 * * * *` to `@reboot`:
```
@reboot /root/scripts/temperature_monitor.sh >> /var/log/temperature_monitor.log 2>&1
```

2. Killed all 132 zombie processes:
```
pkill -f temperature_monitor.sh
```

3. Started one fresh instance:
```
/root/scripts/temperature_monitor.sh >> /var/log/temperature_monitor.log 2>&1 &
```

4. Verified single process running:
```
root@pve-prod:~# ps aux | grep temperature
root  612552  0.0  0.0  7092  3356 pts/0  S  23:05  0:00 /bin/bash /root/scripts/temperature_monitor.sh
```

## Lesson — Daemon vs Cron Job

The four watchdog scripts on this host use two patterns:

| Script | Type | Schedule | Why |
|--------|------|----------|-----|
| temperature_monitor.sh | Daemon | @reboot | Tracks consecutive hot readings (state between checks) |
| io-storm-watchdog.sh | Daemon | @reboot | Tracks consecutive IO hits + cooldown timers (state between checks) |
| dr_ups_monitor.sh | Cron job | */5 * * * * | Each run is independent — reads battery, decides, exits |
| backup-proxmox-config.sh | Cron job | Thu/Sat 21:00 | Each run is independent — collects, tars, exits |

**Rule:** If the script has `while true` (daemon), use `@reboot`. If the script runs and exits (cron job), use a schedule. Mixing them creates fork bombs.

---

## Related

- TS-PVE-013: UPS monitor had wrong cron (weekly vs */5) — same category of cron misconfiguration
- TS-PVE-015: vzdump thermal shutdown — the temperature monitor this ticket is about
