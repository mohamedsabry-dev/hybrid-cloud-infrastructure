# Thermal DR

CPU temperature monitoring for the laptop-Proxmox hosts. Peer to
[`../power/`](../power/) — both are host-level prevention scripts for
environmental failures on this form factor.

## What it does

Reads `thermal_zone0` every 5 minutes from cron. Three branches:

| Temp | Action |
|------|--------|
| > 78 °C | Send critical email + graceful shutdown (`shutdown -h +1`, 1-minute delay so VMs wind down cleanly) |
| > 73 °C | Send warning email (no shutdown) |
| ≤ 73 °C | Log only |

Email uses `mail -s … << EOF … EOF`, same pattern as `../power/dr_ups_monitor.sh`
and `../../backup/proxmox_backup/backup-proxmox-config.sh`. Relay must already
be configured via [`../../bootstrap_proxmox/mail-config-guide.txt`](../../bootstrap_proxmox/mail-config-guide.txt).

## Files

| File | Purpose |
|------|---------|
| `temperature_monitor.sh` | The monitor script |
| `thermal-monitor-setup-guide.txt` | Install, cron schedule, manual check |

## Related

- [`../README.md`](../README.md) — parent DR scope
- [`../power/`](../power/) — sibling monitor (UPS / battery)
