# Power DR — UPS / Battery Monitor

UPS monitoring for Proxmox running on laptop hardware. The laptop's
internal battery IS the UPS — the `dr_ups_monitor.sh` script watches
battery state and triggers a graceful shutdown when a site-wide outage
is confirmed (via a network probe at the warning threshold).

For why the script decides what it decides (thresholds, discharging-only
rule, 3-host network probe), see [`DESIGN.md`](DESIGN.md). For install
and run commands see [`ups-monitor-setup-guide.txt`](ups-monitor-setup-guide.txt).

## Files

| File | Purpose |
|------|---------|
| `dr_ups_monitor.sh` | The monitor script (read battery, decide, shut down if needed) |
| `DESIGN.md` | Threshold model + network-probe rationale + scope boundary |
| `ups-monitor-setup-guide.txt` | Install / cron / test / troubleshoot commands |

## Related

- [`../README.md`](../README.md) — parent DR scope (power + thermal + hardware + recovery)
- [`../thermal/`](../thermal/) — sibling concern (CPU temperature monitoring)
