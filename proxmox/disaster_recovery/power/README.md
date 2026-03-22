# Power Outage DR

UPS/battery monitoring for Proxmox on laptop hardware.

## Overview

Proxmox installed bare-metal on laptop uses the laptop battery as a UPS.
The `dr_ups_monitor.sh` script detects power outages and triggers safe shutdown before battery dies.

## Quick Setup

```bash
# 1. Create scripts directory
mkdir -p /root/scripts

# 2. Copy script to Proxmox hosts
scp dr_ups_monitor.sh root@pve-dev:/root/scripts/
scp dr_ups_monitor.sh root@pve-prod:/root/scripts/

# 3. Make executable
chmod +x /root/scripts/dr_ups_monitor.sh

# 4. Add cron job (runs every 5 min)
crontab -e
# Add this line:
*/5 * * * * /root/scripts/dr_ups_monitor.sh >> /var/log/dr_ups.log 2>&1

# 5. Verify cron was added
crontab -l

# 6. Test
/root/scripts/dr_ups_monitor.sh
```

## How It Works

### Battery Detection

Linux exposes battery info at:
```
/sys/class/power_supply/BAT*/status    → Charging, Discharging, Full
/sys/class/power_supply/BAT*/capacity  → 0-100 (percentage)
```

### Key Decision: Discharging Check

Only trigger shutdown if battery is **DISCHARGING** (going down).
If battery is "Charging" at 40%, power is BACK - don't shutdown!

### Battery Thresholds

| Level | Threshold | Action | Reason |
|-------|-----------|--------|--------|
| CRITICAL | < 35% | Force halt NOW | No time left, save disks |
| LOW | < 55% | Graceful shutdown | Power definitely lost |
| WARNING | < 78% | Check network first | Maybe just unplugged briefly |
| NORMAL | > 78% | Monitor only | Plenty of time |

### Network Check Logic (at 78%)

When battery < 78% AND discharging:
- Ping 3 hosts: `10.0.5.1` (gateway), `10.0.40.120` (NAS), `8.8.8.8` (internet)
- Check every 10 seconds for 2 minutes (12 rounds)
- If ANY host responds → Network up, maybe just unplugged charger
- If ALL fail for 2 min → Full site power outage, trigger shutdown

### Why 3 Different Hosts?

| Host | Purpose |
|------|---------|
| `10.0.5.1` | Local gateway |
| `10.0.40.120` | NAS (another local device) |
| `8.8.8.8` | Internet (confirms external is also down) |

## Technical Details

### Lock File
`/tmp/dr_ups_monitor.lock` prevents multiple script instances.

### Cron Schedule
`*/5 * * * *` → Every 5 minutes. Cron auto-starts on boot.

### Log File
`/var/log/dr_ups.log` - all output with timestamps.

## Troubleshooting

```bash
# Check battery status manually
cat /sys/class/power_supply/BAT*/status
cat /sys/class/power_supply/BAT*/capacity

# Check recent logs
tail -50 /var/log/dr_ups.log

# Test script manually
/root/scripts/dr_ups_monitor.sh

# Verify cron is running
crontab -l
systemctl status cron
```

## Files

| File | Purpose |
|------|---------|
| `dr_ups_monitor.sh` | Main monitoring script |
