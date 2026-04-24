# IO Storm Watchdog

Detects the VM causing an IO cascade on the shared NVMe and force-resets it.
This is the safety net that came out of the 7-hour IO storm investigation
(TS-PVE-017) — the IO throttle contains the blast radius, this script catches
the source and kills it before the whole environment goes down.

## How it works

Runs as a daemon via cron `@reboot`, checks every 30 seconds. Two detection
rules:

**Rule 1 — IO storm (3+ victims).** When 3 or more VMs show IO pressure above
15%, there's a system-wide cascade. The script looks for the source: the K8s VM
with IO pressure *below* 2% but CPU *above* 40%. That fingerprint (high CPU,
low IO) means it's generating IO, not suffering from it. If the pattern holds
for 4 consecutive checks (2 min), reset the VM.

**Rule 2 — CPU stuck (single VM).** When the IO throttle works too well, the
source VM gets isolated but stuck at >300% CPU in a loop. No other VMs are
affected (throttle contained the IO), so Rule 1 never fires. Rule 2 catches
this: single K8s VM above 300% CPU for 4 consecutive checks → reset.

Both rules send an email alert on action, sleep 3 minutes for cooldown, then
run 4 recovery checks to confirm the environment stabilized. Recovery
confirmation also gets emailed.

## Detection fingerprint

| Signal | Source VM | Victim VMs |
|--------|-----------|------------|
| IO pressure | < 2% (generating, not receiving) | > 15% (suffering) |
| CPU | > 40% (actively working) | Low-moderate |

## Files

| File | Purpose |
|------|---------|
| `io-storm-watchdog.sh` | The watchdog daemon (30s loop, 2 rules, email + reset + recovery check) |

## Related

- [`../README.md`](../README.md) — parent DR scope
- [`../thermal/`](../thermal/) — sibling monitor (CPU temperature)
- [`../../../troubleshooting/proxmox/17-proxmox-host-cpu-io-spike-vms-stuck.md`](../../../troubleshooting/proxmox/17-proxmox-host-cpu-io-spike-vms-stuck.md) — the investigation that led to this script
- [`../../bootstrap_proxmox/mail-config-guide.txt`](../../bootstrap_proxmox/mail-config-guide.txt) — mail relay setup (prereq for alert emails)
