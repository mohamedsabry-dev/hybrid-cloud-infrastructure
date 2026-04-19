# Thermal DR

CPU temperature monitoring for the laptop-Proxmox hosts. Peer to [`../power/`](../power/) — both are host-level prevention scripts for environmental failures on this form factor.

## What it does

Reads `thermal_zone0` every 5 minutes from cron. Two branches:

| Temp | Action |
|------|--------|
| > 78 °C | Send critical email + graceful shutdown (`shutdown -h +1`, 1-minute delay so VMs wind down cleanly) |
| > 73 °C | Send warning email (no shutdown) |
| ≤ 73 °C | Log only |

Email uses `mail -s … << EOF … EOF`, same pattern as [`../power/dr_ups_monitor.sh`](../power/dr_ups_monitor.sh) and [`../../backup/proxmox_backup/backup-proxmox-config.sh`](../../backup/proxmox_backup/backup-proxmox-config.sh). Relay must already be configured via [`../../bootstrap_proxmox/mail-config.sh`](../../bootstrap_proxmox/mail-config.sh).

## Install

```bash
mkdir -p /root/scripts
scp temperature_monitor.sh root@pve-dev:/root/scripts/
scp temperature_monitor.sh root@pve-prod:/root/scripts/
chmod +x /root/scripts/temperature_monitor.sh

crontab -e
# */5 * * * * /root/scripts/temperature_monitor.sh >> /var/log/temperature_monitor.log 2>&1
```

## Check manually

```bash
cat /sys/class/thermal/thermal_zone0/temp              # raw milli-°C
/root/scripts/temperature_monitor.sh                    # one-shot run
tail -20 /var/log/temperature_monitor.log               # recent readings
```
