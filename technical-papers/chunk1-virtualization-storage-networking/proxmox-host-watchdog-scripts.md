Proxmox Host Watchdog Scripts — Cron-Driven Detection and Response (Summary Trace)
====================================================================================

pre-trace (one-time setup):
  Postfix → Gmail SMTP relay configured (bootstrap mail-config.sh)
    → scripts deployed to /root/scripts/, cron entries added
    → logs to /var/log/<script>.log, emails to mohamedsabry.dev@gmail.com

--- scenario 1: temperature monitor (daemon, @reboot, pve-prod only) ---
script: temperature_monitor.sh → /root/scripts/temperature_monitor.sh

  starts at boot (@reboot cron) → runs as daemon (infinite loop, never exits)
    → reads /sys/class/thermal/thermal_zone0/temp every 30s
      → < 90°C: silent (no log), reset counter
      → >= 90°C: check pgrep -f vzdump|qmrestore
        → backup active: skip (TS-PVE-015: ZSTD compression spikes to 92°C expected)
        → no backup + sustained 5 min (10 checks × 30s): send critical email
          → /sbin/shutdown -h +1 → single dip below 90°C resets counter completely
  → TS-PVE-023: was misconfigured as */5 cron → 132 zombie daemons accumulated

--- scenario 2: UPS/battery monitor (cron */5 * * * *, both hosts) ---
script: dr_ups_monitor.sh → /root/scripts/dr_ups_monitor.sh

  cron fires every 5 min → script runs, checks, exits
    → lock file prevents overlapping runs
    → reads /sys/class/power_supply/BAT*/status + BAT*/capacity
      → Charging/Full: exit → Discharging: evaluate level
        → < 35%: force halt NOW → < 55%: graceful shutdown +1 min
        → < 78%: network probe (gateway + NAS + 8.8.8.8 for 2 min)
          → any peer responds: just unplugged, exit
          → all fail 2 min: site outage confirmed → shutdown +1
        → >= 78%: log only
      → TS-PVE-013: prod had wrong cron (weekly vs */5), missed real outage

--- scenario 3: IO storm watchdog (daemon, @reboot, pve-dev only) ---
script: io-storm-watchdog.sh → /root/scripts/io-storm-watchdog.sh
monitors: 1001 (FreeIPA) + 1010-1012 (masters) + 1020-1022 (workers)

  starts at boot (@reboot cron) → runs as daemon (infinite loop, never exits)
    → 15-min startup delay → checks every 30s via pvesh API

  Rule 1 — IO storm (system-wide cascade, TS-PVE-017):
    step 1: read IO pressure for all 7 VMs via pvesh
      → count victims: IO pressure > 15% = VM is waiting for IO (suffering)
    step 2: 3+ victims? → system-wide IO distress confirmed
    step 3: find the source among k8s VMs (counter-intuitive):
      → source has LOW IO (<2%) — its IO is going through, not waiting
        → but low IO alone could be idle (like FreeIPA doing nothing)
          → also check CPU > 40% — low IO + high CPU = actively hogging NVMe
    step 4: same suspect VM for 4 consecutive checks (2 min) → confirmed
      → single clean check resets all suspects (storm subsided)
    step 5: qm reset <vmid> → evidence snapshot email → 3-min cooldown
    step 6: 4 clean recovery checks → recovery email

  Rule 2 — CPU stuck (contained storm):
    fires only when NO system-wide IO distress (Rule 1 didn't trigger)
      → IO throttle contained the blast — other VMs fine
        → but one k8s VM stuck at CPU > 300% (4 vCPUs maxed, spinning)
    same pattern: 4 consecutive hits → reset → cooldown → verify

  state tracked in /tmp files (suspect VMID + hit count per rule)

--- scenario 4: config backup (cron Thu/Sat 21:00, both hosts) ---
script: config_backup.sh → /root/scripts/config_backup.sh

  cron fires Thu + Sat at 21:00 → script runs, collects, exits
    → collects /etc/pve + network + storage + boot + SSH + cron + systemd
      → tar.gz → /mnt/pve/nas-backups/dump/ via NFS (VLAN 40)
        → keeps last 5 per host → restore: fresh install → bootstrap → extract
