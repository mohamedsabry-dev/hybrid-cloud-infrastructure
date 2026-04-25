# Power DR — design notes

Why the UPS / battery monitoring script on the laptop-Proxmox hosts makes
the decisions it does.

---

## Laptop battery IS the UPS

Proxmox is installed bare-metal on laptops. No external UPS is wired in —
the laptop's internal battery plays that role. Linux exposes battery state
at:

  /sys/class/power_supply/BAT*/status     → Charging / Discharging / Full
  /sys/class/power_supply/BAT*/capacity   → 0–100 (%)

The monitor script reads those two files, which is enough signal without
any extra daemon, APC tooling, or serial connection.

## Shutdown only when DISCHARGING

The single most important rule: only trigger shutdown if the battery is
actually draining. A battery at 40% that's `Charging` means power is BACK
(maybe a brief AC interruption), and shutting down would be exactly the
wrong thing. The `status` field gate is what prevents false-positive
shutdowns during brief power blips.

## Four-tier threshold model

| Level | % | Action | Why |
|-------|---|--------|-----|
| CRITICAL | < 35% | `halt` immediately, no grace | Not enough time to shut down gracefully; priority is saving the disks |
| LOW | < 55% | Graceful shutdown | Power is definitely lost; enough battery to shut down cleanly |
| WARNING | < 78% | Network-probe first, then decide | Might just be briefly unplugged; verify before acting |
| NORMAL | ≥ 78% | Log only | Plenty of battery, no decision needed |

The 78% warning threshold exists specifically to handle the "someone
unplugged the laptop for 30 seconds to move it" case — common and NOT
worth a shutdown. Dropping to 55% means the discharge has been going on
long enough that it's not just a brief unplug.

## Why a network probe at the warning tier

Between 78% and 55%, the script doesn't trust the battery level alone —
it asks "is the network also down?" Pings three hosts over 2 minutes:

| Host | Why |
|------|-----|
| `10.0.5.1` | Local gateway — any reachable device confirms local network is alive |
| `10.0.40.120` | NAS — a second local device, redundancy against one host being off |
| `8.8.8.8` | Public internet — confirms power outage is BROADER than just this laptop |

If ANY host responds → network is up → treat as "laptop unplugged, rest of
house is fine" → don't shut down. If ALL three fail for 2 minutes → assume
a site-wide power outage and shut down gracefully.

This is the highest-ROI decision in the script: it prevents unnecessary
shutdowns when the most common cause of battery discharge is just someone
moving the laptop for a few minutes.

## Lock file, cron, logging

- **Lock file** at `/tmp/dr_ups_monitor.lock` prevents multiple concurrent
  runs. Cron-fired scripts on a struggling system can stack; the lock is
  cheap insurance.
- **Cron cadence**: every 5 min. Tight enough to catch a fast discharge,
  loose enough to not hammer `cat /sys/...` pointlessly.
- **Log file** at `/var/log/dr_ups.log` — timestamped per-run output. The
  log is where post-incident analysis happens ("when did the script
  actually fire and why").

## What this script DOESN'T try to do

- Communicate with UPS firmware / APC daemons — laptop batteries don't
  expose that
- Send emails — that's handled separately via the mail-config / postfix
  path; this script just shuts the host down
- Decide WHICH VMs to shut down first — Proxmox `onboot`/`shutdown` order
  owns that

Scope is intentionally narrow: detect sustained discharge → trigger
graceful shutdown at the right moment.
