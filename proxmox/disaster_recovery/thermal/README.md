# Thermal DR — CPU Temperature Monitor

CPU temperature monitoring for the laptop-Proxmox hosts. Peer to
[`../power/`](../power/) — both are host-level prevention scripts for
environmental failures on this form factor.

## What it does

Runs as a daemon via cron `@reboot`. Reads `thermal_zone0` every 30 seconds
and tracks how long the CPU stays above 90°C. Won't act on brief spikes —
only triggers shutdown after 5 minutes of sustained heat with no known
cause.

The key safety: if `vzdump` or `qmrestore` is running, the script skips
that reading entirely. Backup jobs spike CPU heat but that's expected
behavior, not a thermal emergency. This came from TS-PVE-018 where the
original draft script shut down the host mid-backup.

| Condition | Action |
|-----------|--------|
| >= 90°C, backup/restore running | Log + skip (spike is expected) |
| >= 90°C, no backup, first hit | Send warning email, start counting |
| >= 90°C, sustained 5 min (10 checks) | Send critical email + `shutdown -h +1` |
| < 90°C | Reset counter, clear alert state |

Email uses `mail -s … << EOF … EOF`, same pattern as `../power/dr_ups_monitor.sh`
and `../../backup/proxmox_backup/backup-proxmox-config.sh`. Relay must already
be configured via [`../../bootstrap_proxmox/mail-config-guide.txt`](../../bootstrap_proxmox/mail-config-guide.txt).

## Files

| File | Purpose |
|------|---------|
| `temperature_monitor.sh` | The monitor daemon (30s loop, vzdump-aware, email + shutdown) |
| `thermal-monitor-setup-guide.txt` | Install, cron setup, manual check commands |

## Related

- [`../README.md`](../README.md) — parent DR scope
- [`../power/`](../power/) — sibling monitor (UPS / battery)
