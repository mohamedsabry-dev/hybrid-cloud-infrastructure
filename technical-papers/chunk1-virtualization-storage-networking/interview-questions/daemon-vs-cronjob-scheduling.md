Daemon vs Cron Job — When to Use Which and What Breaks When You Mix Them
=========================================================================

Question:
  What's the difference between a daemon and a cron job? When would you
  choose one over the other? Have you seen what happens when you get it
  wrong?

---

The core difference:

  Daemon: starts once, runs forever. Infinite loop with sleep between
    iterations. The process is always alive. State lives in memory —
    counters, timers, flags persist across checks.

  Cron job: cron fires the script at intervals. Script runs, does its
    work, exits. Next run is a brand new process. No memory of last run.

---

When to use a daemon:

  When the script needs state between checks.

  Temperature monitor (temperature_monitor.sh):
    Checks CPU temp every 30s. Needs to count 10 consecutive readings
    above 90°C before triggering shutdown. The counter (suspect_count)
    lives in a bash variable — survives across iterations because the
    process never exits. If this were a cron job, every run starts with
    suspect_count=0 — you'd never reach 10.

  IO storm watchdog (io-storm-watchdog.sh):
    Checks every 30s. Needs 4 consecutive hits before resetting a VM.
    Then 3-min cooldown timer. Then 4 clean checks for recovery
    confirmation. All of that is in-memory state across iterations.

  Could you use a cron job with state files? Yes — write suspect_count
  to /tmp/temp_state, read it back next run. But for 30s intervals
  that's a file read/write every 30 seconds for something a variable
  handles in memory. Cron's minimum is also 1 minute — can't do 30s.

---

When to use a cron job:

  When each run is independent — no memory needed.

  UPS monitor (dr_ups_monitor.sh, */5 * * * *):
    Reads battery status right now. "Am I discharging below 55%?" is a
    complete question. Doesn't need to know what last check said.
    Runs, decides, exits. Next run in 5 min is a fresh process.

  Config backup (backup-proxmox-config.sh, Thu/Sat 21:00):
    Collects files, tars, exits. No relationship to previous runs.

  Bonus: if a cron script crashes, next tick fires a fresh one. If a
  daemon crashes at 2am, it's dead until reboot (unless you add a
  systemd service with Restart=always or a cron watchdog — for your
  watchdog).

---

What happens when you mix them — real incident (TS-PVE-023):

  temperature_monitor.sh is a daemon (while true + sleep 30). But the
  crontab had it as */5 * * * * instead of @reboot.

  What happened:
    12:00 — cron fires instance #1 → enters infinite loop, never exits
    12:05 — cron fires instance #2 → also enters infinite loop
    12:10 — cron fires instance #3
    ...
    23:00 — 132 instances running simultaneously

  Each one independently reading /sys/class/thermal/thermal_zone0/temp
  every 30s. If temp hit 90°C sustained, all 132 would independently
  send critical emails and trigger shutdown.

  Evidence: ps aux showed 264 processes (132 sh wrappers + 132 bash
  scripts), spawned every 5 minutes since boot.

  The irony: io-storm-watchdog.sh on the same host, same daemon pattern,
  was correctly set to @reboot. The temperature line was likely
  copy-pasted from the UPS monitor entry (*/5) without changing the
  schedule.

  Fix: change to @reboot, pkill all zombies, start one fresh instance.

---

The rule:

  Does the script have `while true`? → @reboot (daemon)
  Does the script run and exit? → scheduled cron (*/5, daily, etc.)

  Mixing them = fork bomb. Each cron tick adds another immortal process.

---

Environment examples:

  Script                    Type       Schedule        State needed
  temperature_monitor.sh    Daemon     @reboot         suspect_count across checks
  io-storm-watchdog.sh      Daemon     @reboot         hit counters + cooldown timers
  dr_ups_monitor.sh         Cron job   */5 * * * *     None — reads battery, decides, exits
  backup-proxmox-config.sh  Cron job   Thu/Sat 21:00   None — collects, tars, exits

  Related: TS-PVE-023 (daemon as cron fork bomb)
           TS-PVE-013 (UPS monitor wrong cron — weekly vs */5)
