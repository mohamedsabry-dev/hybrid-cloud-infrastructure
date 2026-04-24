# TS-PVE-017 | 2026-04-19 | ROOT CAUSE CONFIRMED | INCIDENT
_____________________________________________________________________

[Info]
Domain: Proxmox VE / Host Stability
Sub-techs: QEMU, KVM, qemu-ga, IO wait, VM boot hang
Environment: DEV Proxmox server (pve-dev)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Proxmox host hit a severe CPU and IO spike — all VMs became unresponsive.
VMs stuck at "Booting Rocky Linux" screen, unable to progress past kernel load.
Multiple K8s masters showed segfaults before going completely stuck.

Symptoms:
```
1010 (master1) - 99.0% CPU
1011 (master2) - 98.7% CPU
```

```
rs:main Q:Reg[1192]: segfault at 0 ip 0000560a9e7b60ab sp 00007f6785596b470 error 4 in rsyslogd
```

```
haproxy[1218]: backend k8s_masters has no server available!
```

_____________________________________________________________________

[Analysis]

# Step 1: Timeline

| Time | Event |
|------|-------|
| 2026-04-18 ~23:00 | Started DR testing (multiple node shutdowns/restarts) |
| 2026-04-19 ~00:15 | DR Test 4 completed successfully |
| 2026-04-19 ~00:50 | Noticed API server issues on master1 |
| 2026-04-19 ~00:55 | API server crash loop, "no relationship found" errors |
| 2026-04-19 ~01:00 | HAProxy reporting no masters available |
| 2026-04-19 ~01:05 | Attempted VM resets — VMs stuck at boot |
| 2026-04-19 ~01:10 | Identified Proxmox host CPU/IO spike |
| 2026-04-19 ~01:15 | Rebooted Proxmox host |

This happened right after extended DR testing — multiple shutdown/start cycles
over 2 days.

# Step 2: Host-level evidence

```bash
ps aux | grep qemu
1010 (master1) - 99.0% CPU
1011 (master2) - 98.7% CPU
1012 (master3) - 54.6% CPU
```

qemu-ga not responding on any VM:
```bash
qm guest cmd 1010 ping
QEMU guest agent is not running
```

IO wait was above 50% on the host.

# Step 3: Suspected contributing factors

1. Extended DR testing — multiple shutdown/start cycles stressed the host
2. qemu-ga EAGAIN busy loop — multiple occurrences documented (TS-K8S-038)
3. High VM churn — frequent pod evictions, restarts, scheduling
4. Possible resource exhaustion on Proxmox host

# Step 4: What I don't know

- Exact trigger for the host instability
- Whether qemu-ga loops caused cascading host issues
- If there was memory exhaustion on the host
- If NFS storage contributed

_____________________________________________________________________

[Final Root Cause]
CONFIRMED (2026-04-24, 8-hour investigation).

Zero IO isolation on shared consumer NVMe combined with Kubernetes cascade dynamics.
Single 476.9GB NVMe with LVM-thin pool, 15+ VM disks, ALL Proxmox IO throttles set
to unlimited. Any single VM can monopolize the entire NVMe queue, starving all other
VMs and triggering a self-sustaining cascade (probe failures → restarts → LIST storms
→ etcd IO → more probe failures → loop).

Empirically proven: CPU stress on all 3 masters (80% host CPU) = 0% IO spike.
LIST operation spam (100x concurrent) = instant 57% IO spike, 1343ms NVMe latency.
Single VM configmap write storm = host-wide IO delay, all SSH/VNC unresponsive.

qemu-ga (TS-K8S-038) ruled out as direct cause for this occurrence (0% CPU, etcd
slow 7 min before qemu-ga gap). Remains a potential indirect trigger for future events.

Full investigation: troubleshooting/proxmox/17-root-cause-investigation/

_____________________________________________________________________

[Final Solution]

Rebooted Proxmox host:
```bash
reboot
```

After reboot all VMs started normally, K8s cluster recovered, no further issues.

Next occurrence — collect these before rebooting:
```bash
journalctl -u pvedaemon --since "1 hour ago"
journalctl -u pveproxy --since "1 hour ago"
dmesg | grep -iE "error|fail|oom"
```

Verified: Yes — all VMs recovered after host reboot.

_____________________________________________________________________

[Risk Level] HIGH (until IO throttling applied)

Root cause confirmed but fix NOT YET APPLIED. Will recur from any trigger that
generates heavy IO on a single VM (backup, qemu-ga, restart storm, Flux retry).
Per-VM IO throttling via Proxmox Hardware → Disk → Bandwidth tab is the primary fix.
See troubleshooting/proxmox/17-root-cause-investigation/05-remediation-stages.md.

_____________________________________________________________________

[References]
- TS-K8S-038 — qemu-ga EAGAIN busy loop (potential indirect trigger, not direct cause)
- TS-K8S-043 — DR testing that preceded this incident
- TS-PVE-015 — backup IO impact (same architectural weakness, confirmed 40% IO during backup)
- TS-PVE-018 — prod thermal shutdown during backup (same root cause family)
- TS-K8S-042 — Flux retry storm (same cascade pattern, different trigger)
- Full investigation: troubleshooting/proxmox/17-root-cause-investigation/
