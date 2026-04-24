# TS-PVE-018 | 2026-04-23 | RESOLVED | INCIDENT
_____________________________________________________________________

[Info]
Domain: Proxmox VE / vzdump backup / Thermal Management
Sub-techs: vzdump backup job, zstd compression, temperature_monitor.sh, ASUS laptop server
Environment: pve-prod
Re-opened: No

_____________________________________________________________________

[Issue Description]
REAL INCIDENT -- occurred during unplanned production failure, not planned DR testing.

Prod Proxmox server (pve-prod) shut down gracefully during scheduled backup job
at 21:06. System did NOT auto-restart — stayed down until manual boot at 21:16.
All VMs shut down in sequence (ordered systemd shutdown), backup of VM 1020
(k8s-worker1) failed mid-write ("interrupted by signal"). Remaining 8 VMs/CTs
never backed up.

```
# System uptime after manual restart
root@pve-prod:~# uptime
 21:31:21 up 14 min,  1 user,  load average: 1.67, 1.31, 0.59

# Boot history confirms graceful shutdown, not crash
root@pve-prod:~# last reboot
reboot   system boot  6.17.9-1-pve     Thu Apr 23 21:16 - still running
reboot   system boot  6.17.9-1-pve     Thu Apr 23 14:01 - 21:06  (07:04)
```

Session ran 07:04 (14:01 → 21:06). Clean shutdown at 21:06, not a crash.

Impact: VM 1020 backup failed. VMs 1021, 1022, 2001-2006, 9000-9010 never
backed up. Full environment offline for 10 minutes (21:06 → 21:16).

_____________________________________________________________________

[Analysis]

# Step 1: Rule out power loss
```
cat /var/log/dr_ups.log | tail -50
Thu Apr 23 08:55:01 PM EET 2026 - Battery: Full at 100%
[OK] Battery is Full - power connected, no action
Thu Apr 23 09:00:01 PM EET 2026 - Battery: Full at 100%
[OK] Battery is Full - power connected, no action
Thu Apr 23 09:05:01 PM EET 2026 - Battery: Full at 100%
[OK] Battery is Full - power connected, no action
Thu Apr 23 09:20:01 PM EET 2026 - Battery: Full at 100%
[OK] Battery is Full - power connected, no action
```
Battery at 100% throughout. Note the gap from 9:05 → 9:20 — that's the
downtime window visible in the UPS log (system was off, cron couldn't run).
UPS monitor script not involved.

# Step 2: Rule out remediation pod
```
kubectl logs remediation-56bdddfcd7-sprpx -n remediation --previous
--- Health check at 2026-04-23 18:58:31 ---
k8s-worker1.lab.local: Healthy
k8s-worker2.lab.local: Healthy
k8s-worker3.lab.local: Healthy

--- Health check at 2026-04-23 19:03:32 ---
k8s-worker1.lab.local: Healthy
k8s-worker2.lab.local: Healthy
k8s-worker3.lab.local: Healthy
```
Last check before shutdown — all healthy, no action taken.

Confirmed via Proxmox task log — no external API calls triggered any VM operation:
```
pvesh get /nodes/pve-prod/tasks --vmid 1020 --limit 10 --output-format text
│ 1020 │ pve-prod │   8207 │   73839 │ 2026-04-23 21:28:54 │ qmstart    │ root@pam │ OK │
│ 1020 │ pve-prod │ 211849 │ 2548534 │ 2026-04-23 21:06:11 │ qmshutdown │ root@pam │ OK │
│ 1020 │ pve-prod │   8136 │   73830 │ 2026-04-23 14:13:44 │ qmstart    │ root@pam │ OK │
```
21:06:11 qmshutdown was systemd's ordered shutdown, not an API call.
No qmreboot/qmreset from remediation token visible. Remediation not guilty.

Note: the risk of remediation pod colliding with backup suspend phase is real
though — if the 5-minute health check fires during vzdump "suspend vm to make
snapshot", the worker could appear unresponsive and remediation could try to
act. Raised as preventive ticket TS-K8S-050.

# Step 3: Check cron logs leading up to crash
```
Apr 23 20:50:01 pve-prod CRON[203468]: (root) CMD (/root/scripts/temperature_monitor.sh)
Apr 23 20:50:01 pve-prod CRON[203469]: (root) CMD (/root/scripts/dr_ups_monitor.sh)
Apr 23 20:55:01 pve-prod CRON[205933]: (root) CMD (/root/scripts/dr_ups_monitor.sh)
Apr 23 20:55:01 pve-prod CRON[205934]: (root) CMD (/root/scripts/temperature_monitor.sh)
Apr 23 21:00:01 pve-prod CRON[208397]: (root) CMD (/root/scripts/temperature_monitor.sh)
Apr 23 21:00:01 pve-prod CRON[208399]: (root) CMD (/root/scripts/backup-proxmox-config.sh)
Apr 23 21:00:01 pve-prod CRON[208398]: (root) CMD (/root/scripts/dr_ups_monitor.sh)
Apr 23 21:05:01 pve-prod CRON[210978]: (root) CMD (/root/scripts/temperature_monitor.sh)
Apr 23 21:05:01 pve-prod CRON[210979]: (root) CMD (/root/scripts/dr_ups_monitor.sh)
Apr 23 21:06:01 pve-prod systemd[1]: Stopping cron.service...
Apr 23 21:06:01 pve-prod systemd[1]: Stopped cron.service.
-- Boot acb95bf667054e6c8fd340cb6fcf148c --
```
Normal cron execution at 20:50, 20:55, 21:00. At 21:05 the temperature script
fired during active backup — this is the trigger. By 21:06 cron is being
stopped as part of shutdown sequence. Boot boundary visible in journal.

# Step 4: Find the smoking gun
```
journalctl -b -1 --no-pager | grep -iE "shutdown|halt|power"
Apr 23 21:06:01 pve-prod systemd-logind[871]: System is powering down
  (CPU temperature 91°C - graceful thermal shutdown).
```

Root cause identified. temperature_monitor.sh (cron */5) detected CPU at 91°C,
exceeding its 80°C threshold. Script triggered:
`/sbin/shutdown -h +1 "CPU temperature 91°C - graceful thermal shutdown"`

# Step 5: Full sequence at 21:05 — the minute before shutdown
```
Apr 23 21:04:25 pvescheduler: Starting Backup of VM 1020 (qemu)
Apr 23 21:05:01 CRON: temperature_monitor.sh    <-- detected overtemp
Apr 23 21:05:01 CRON: dr_ups_monitor.sh         <-- battery 100%, no action
Apr 23 21:05:01 systemd-logind[871]: Suspending...
Apr 23 21:05:01 systemd-logind[871]: Unit suspend.target is masked, refusing operation.
Apr 23 21:05:01 systemd-logind[871]: Failed to execute suspend operation: Permission denied
Apr 23 21:05:01 systemd-logind[871]: Creating /run/nologin, blocking further logins...
Apr 23 21:05:01 systemd-logind[871]: Suspending...
Apr 23 21:05:01 systemd-logind[871]: Unit suspend.target is masked, refusing operation.
Apr 23 21:05:01 systemd-logind[871]: Failed to execute suspend operation: Permission denied
Apr 23 21:05:01 systemd-logind[871]: Suspending...
Apr 23 21:05:01 systemd-logind[871]: Unit suspend.target is masked, refusing operation.
Apr 23 21:05:01 systemd-logind[871]: Failed to execute suspend operation: Permission denied
Apr 23 21:05:01 postfix/pickup: 4AB44500F31: uid=0 from=<root>
Apr 23 21:05:04 postfix/smtp: 4AB44500F31: to=<mohamedsabry.dev@gmail.com>,
  relay=smtp.gmail.com[74.125.206.108]:587, delay=3.2, status=sent (250 2.0.0 OK)
Apr 23 21:06:01 systemd-logind[871]: System is powering down
  (CPU temperature 91°C - graceful thermal shutdown).
```

Three suspend attempts at 21:05:01 — laptop lid sensor noise, all masked
(suspend.target is masked on servers). Not related to the shutdown, but adds
to the log noise. The email alert was successfully sent to Gmail 3.2s after
the temperature script detected the overtemp condition.

# Step 6: Reconstruct the full timeline
```
21:00:01  Cron: temperature_monitor.sh runs — temp normal (backup hadn't spiked yet)
21:00:01  Cron: dr_ups_monitor.sh runs — battery 100%
21:00:01  Cron: backup-proxmox-config.sh runs (config backup, not vzdump)
21:00:03  vzdump starts: --all --mode snapshot --compress zstd --storage nas-prod-data
21:00:03  VM 1001 (freeipa) backup starts      → 21:01:27 (1m24s)  OK   1.61 GB
21:01:27  VM 1010 (k8s-master1) backup starts   → 21:02:22 (55s)    OK   3.50 GB
21:02:22  VM 1011 (k8s-master2) backup starts   → 21:03:18 (56s)    OK   3.63 GB
21:03:19  VM 1012 (k8s-master3) backup starts   → 21:04:25 (1m07s)  OK   3.71 GB
21:04:25  VM 1020 (k8s-worker1) backup starts   → zstd compression running...
21:05:01  Cron: temperature_monitor.sh fires — CPU >80°C → triggers shutdown -h +1
21:05:01  3x suspend attempts (lid sensor, all masked)
21:05:01  /run/nologin created (blocking further logins)
21:05:04  Email alert sent via smtp.gmail.com
21:06:01  systemd-logind: "System is powering down (CPU temperature 91°C)"
21:06:01  Ordered systemd shutdown begins — services stop in sequence
21:06:09  vzdump: "Backup of VM 1020 failed - interrupted by signal"
21:06:11  VM 1020 qmshutdown (graceful)
21:08:02  NAS unmounted (/mnt/pve/nas-backups)
21:08:xx  System halted
21:16:xx  Manual boot
21:28:54  VM 1020 manually started
```

# Step 7: vzdump backup summary (from email notification)
```
VMID  Name         Status  Time     Size      Filename
1001  freeipa      ok      1m 24s   1.608 GiB vzdump-qemu-1001-2026_04_23-21_00_03.vma.zst
1010  k8s-master1  ok      55s      3.499 GiB vzdump-qemu-1010-2026_04_23-21_01_27.vma.zst
1011  k8s-master2  ok      56s      3.627 GiB vzdump-qemu-1011-2026_04_23-21_02_22.vma.zst
1012  k8s-master3  ok      1m 7s    3.708 GiB vzdump-qemu-1012-2026_04_23-21_03_18.vma.zst
1020  k8s-worker1  err     1m 44s   0 B       (interrupted by signal)
1021  VM 1021      todo    <0.1s    0 B
1022  VM 1022      todo    <0.1s    0 B
2001-2006           todo    <0.1s    0 B       (LXCs never started)
9000-9010           todo    <0.1s    0 B       (templates never started)

Total running time: 6m 6s
Total size: 12.442 GiB (incomplete — only 4 of 16 succeeded)
```

The crash point was the first worker node (VM 1020). All 4 master/freeipa VMs
completed successfully. Workers and LXCs never got their turn.

# Step 8: Worker1 backup progress before interruption
```
1020: 21:04:26 INFO: creating vzdump archive '...vzdump-qemu-1020-2026_04_23-21_04_25.vma.zst'
1020: 21:04:26 INFO: issuing guest-agent 'fs-freeze' command
1020: 21:04:26 INFO: issuing guest-agent 'fs-thaw' command
1020: 21:04:26 INFO: started backup task '60b9cfe6-088c-40f9-adf5-3995bd800fff'
1020: 21:04:29 INFO:  13% (3.4 GiB of 25.0 GiB) in 3s, read: 1.1 GiB/s, write: 350.2 MiB/s
1020: 21:04:32 INFO:  16% (4.2 GiB of 25.0 GiB) in 6s, read: 286.4 MiB/s, write: 285.3 MiB/s
1020: 21:04:35 INFO:  20% (5.2 GiB of 25.0 GiB) in 9s, read: 351.6 MiB/s, write: 351.5 MiB/s
1020: 21:04:38 INFO:  24% (6.0 GiB of 25.0 GiB) in 12s, read: 281.5 MiB/s, write: 280.5 MiB/s
1020: 21:04:41 INFO:  31% (8.0 GiB of 25.0 GiB) in 15s, read: 656.1 MiB/s, write: 276.9 MiB/s
1020: 21:04:44 INFO:  35% (9.0 GiB of 25.0 GiB) in 18s, read: 342.0 MiB/s, write: 341.9 MiB/s
1020: 21:04:47 INFO:  39% (9.9 GiB of 25.0 GiB) in 21s, read: 315.4 MiB/s, write: 308.7 MiB/s
1020: 21:04:50 INFO:  48% (12.1 GiB of 25.0 GiB) in 24s, read: 754.0 MiB/s, write: 330.3 MiB/s
1020: 21:04:53 INFO:  52% (13.2 GiB of 25.0 GiB) in 27s, read: 357.7 MiB/s, write: 357.7 MiB/s
1020: 21:04:56 INFO:  56% (14.0 GiB of 25.0 GiB) in 30s, read: 293.6 MiB/s, write: 287.7 MiB/s
1020: 21:04:59 INFO:  60% (15.2 GiB of 25.0 GiB) in 33s, read: 404.8 MiB/s, write: 401.8 MiB/s
1020: 21:05:02 INFO:  66% (16.6 GiB of 25.0 GiB) in 36s, read: 465.2 MiB/s, write: 320.6 MiB/s
1020: 21:05:05 INFO:  70% (17.6 GiB of 25.0 GiB) in 39s, read: 367.3 MiB/s, write: 360.6 MiB/s
1020: 21:05:08 INFO: 100% (25.0 GiB of 25.0 GiB) in 42s, read: 2.5 GiB/s, write: 76.3 MiB/s
1020: 21:05:08 INFO: backup is sparse: 12.32 GiB (49%) total zero data
1020: 21:05:08 INFO: transferred 25.00 GiB in 42 seconds (609.6 MiB/s)
1020: 21:06:09 ERROR: Backup of VM 1020 failed - interrupted by signal
```

Backup data transfer actually completed at 21:05:08 (100%). The 1-minute gap
between transfer completion (21:05:08) and error (21:06:09) was likely the
archive finalization + NAS write phase, which was interrupted by the shutdown
signal. The zstd compression during the 42-second transfer window is what
drove CPU to 91°C.

# Step 9: Proxmox metrics correlation
From Proxmox GUI graphs during backup window:
- CPU: jumped from avg 7% to 17% at 21:00 when backup started
- IO delay (IO wait): jumped from avg 1% to 11% (sustained ~6 minutes)
- Memory: gradual stepwise reduction during shutdown — smooth curve
  confirming ordered shutdown, not crash (crash would show cliff drop)

The IO delay of 11% on prod caused zero K8s impact — no master degradation,
no CrashLoopBackOff, no pod restarts. Prod hardware handles backup I/O
pressure without affecting running workloads.

# Step 10: Confirm with reproducibility test
Disabled shutdown action in temperature_monitor.sh (commented out), re-ran
vzdump backup while manually checking temperature:

```
22:08:02  CPU: 67°C  (idle, pre-backup)
22:08:28  CPU: 68°C  (backup starting)
22:08:36  CPU: 85°C  (first VM backup — zstd compression kicks in)
22:08:48  CPU: 74°C  (brief dip between VMs)
22:09:10  CPU: 87°C  (second VM backup)
22:09:11  CPU: 89°C
22:09:13  CPU: 91°C  ← would have triggered shutdown again
22:09:15  CPU: 92°C  ← peak
22:09:16  CPU: 87°C  (cooling)
22:10:19  CPU: 84°C
22:10:29  CPU: 70°C  (backup done, cooling down)
22:10:31  CPU: 68°C  (back to normal)
```

Confirmed: vzdump + zstd compression spikes CPU from 65°C idle to 85-92°C
during each VM backup. Each VM takes ~1 minute. Temperature oscillates between
VMs as CPU briefly idles. The 80°C threshold in temperature_monitor.sh will
trigger on every single backup run. Current idle temp post-recovery: 63°C.

# Step 11: Why dev didn't have this problem
Dev (pve-dev) does NOT have temperature_monitor.sh deployed. Dev laptop
normally runs hotter (75-80°C idle) because it's a weaker machine — deploying
an 80°C threshold there would trigger constantly and make the server unusable.
The script was deployed only on prod as a safety net because it's a more
expensive laptop that normally idles at 64-65°C.

This means TS-PVE-015 (dev crash during backup on 2026-04-11) was likely the
same thermal cause but WITHOUT the graceful shutdown — dev hit the hardware
thermal limit (~100°C) causing a hard crash with no logs. Prod was caught at
91°C by the script before hardware cutoff. Same root cause, different failure
mode, explained by presence/absence of one script.

# Step 12: Dev environment backup metrics comparison
Noted on dev during same backup window:
- IO delay: avg 33-38% during 13 minutes of full env backup
- CPU: rose from avg 8% to 16%
- kubectl commands delayed ~3 seconds during backup
- kube-controller-manager and kube-scheduler entered CrashLoopBackOff on
  master2 and master3 for ~10 minutes (see TS-PVE-015 re-opened section)

Prod at 11% IO delay had zero cluster impact. The K8s master degradation is
a dev hardware capacity issue, not a backup-inherent or NAS-related problem.

# Step 13: NAS overwhelm hypothesis — debunked
Initial suspicion was that concurrent backup from both hosts overwhelmed the
NAS. Investigation proved this wrong:
- NAS is a dedicated storage appliance with dedicated switch ports — designed
  for concurrent I/O. A few hundred MB/s from two USB3-to-eth adapters is
  well within its capacity.
- Prod IO delay was only 11% with zero cluster impact — if NAS were the
  bottleneck, IO delay would be much higher.
- The real bottleneck is per-host: zstd CPU compression (thermal) and per-host
  IO capacity (hardware-dependent). The NAS is fine.

_____________________________________________________________________

[Final Root Cause]
temperature_monitor.sh (cron */5) has an 80°C shutdown threshold. vzdump with
zstd compression spikes laptop CPU to 85-92°C during every backup run. The
script correctly detected "overheating" and triggered a graceful shutdown via
`/sbin/shutdown -h +1`. The threshold is too aggressive for a laptop under
legitimate backup I/O load — the 80°C threshold was calibrated for sustained
overheating, not for the 1-minute thermal spikes that backup zstd compression
produces.

This also retroactively explains TS-PVE-015: same thermal cause, but dev has
no temperature script — the CPU hit hardware thermal limit and crashed hard
instead of shutting down gracefully.

_____________________________________________________________________

[Final Solution]
Temporary: Commented out the shutdown action in temperature_monitor.sh on prod
to prevent recurrence during backup window. Script still logs and emails but
does not trigger shutdown.

```bash
#    /sbin/shutdown -h +1 "CPU temperature ${TEMP_C}°C - graceful thermal shutdown"
     echo "Test Temp $TEMP_C"
```

Permanent solution needed (TODO — pick one or combine):
1. Raise threshold to 95°C (above backup spike, below hardware cutoff ~100°C)
2. Add backup-awareness: skip shutdown if vzdump is running
   (`pgrep -f vzdump && exit 0`)
3. Reduce vzdump compression: use lzo instead of zstd (less CPU, bigger files)
4. Add `--bwlimit` to vzdump to throttle I/O and reduce CPU pressure
5. Schedule backups during cooler hours (night vs evening)

Verified: Yes — backup re-ran successfully with shutdown action disabled.
System stable. Temperature returned to 68°C after backup completed.

_____________________________________________________________________

[Risk Level] MEDIUM — temporary fix disables thermal protection entirely.
Need permanent solution before next heatwave or sustained high-load scenario.

_____________________________________________________________________

[References]
- Related: TS-PVE-015 (Dev crash during backup — SAME ROOT CAUSE, different failure mode: hard crash vs graceful shutdown because dev has no temperature script)
- Related: TS-PVE-014 (Worker VM crash unknown cause — may also be thermal)
- Related: TS-PVE-017 (CPU/IO spike during DR testing — similar thermal pattern)
- Child: TS-K8S-050 (Remediation pod vs backup window race condition — preventive, raised from this investigation)
- Related: DR proxmox-vzdump-backup.md (backup validation — updated with thermal findings)
- Script: proxmox/disaster_recovery/thermal/draft-temperature_monitor.sh (threshold: 80°C)
- Script: /root/scripts/temperature_monitor.sh (deployed on pve-prod, shutdown action now commented out)
