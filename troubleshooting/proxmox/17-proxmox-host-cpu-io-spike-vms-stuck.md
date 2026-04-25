# TS-PVE-017 | 2026-04-19 | ROOT CAUSE CONFIRMED | INCIDENT
_____________________________________________________________________

[Info]
Domain: Proxmox VE / Host Stability / IO Architecture
Sub-techs: QEMU, KVM, LVM-thin, NVMe IO contention, K8s cascade dynamics,
           etcd fsync, qemu-ga, PSI (Pressure Stall Information)
Environment: DEV Proxmox server (pve-dev) — single consumer NVMe, 15+ VM disks
Duration: ~8 hours continuous investigation (2026-04-23/24 overnight)
Severity: Critical — full cluster outage, all VMs unresponsive
Re-opened: No
Related: TS-K8S-038, TS-K8S-042, TS-PVE-015, TS-PVE-020

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

Pattern: random IO spikes 40%+ PSI lasting 5-15 min, 2-5 times/week for 2+ weeks.
This particular incident escalated into a full cluster outage.

_____________________________________________________________________

[Analysis]

# Step 1: Incident timeline

| Time | Event |
|------|-------|
| 2026-04-18 ~23:00 | Started DR testing (multiple node shutdowns/restarts) |
| 2026-04-19 ~00:15 | DR Test 4 completed successfully |
| 2026-04-19 ~00:50 | Noticed API server issues on master1 |
| 2026-04-19 ~01:00 | HAProxy reporting no masters available |
| 2026-04-19 ~01:05 | Attempted VM resets — VMs stuck at boot |
| 2026-04-19 ~01:10 | Identified Proxmox host CPU/IO spike |
| 2026-04-19 ~01:15 | Rebooted Proxmox host — VMs recovered |

Came back 4 days later for the real investigation.

| Time | Event |
|------|-------|
| 2026-04-23 ~23:15 | Started 8-hour root cause investigation |
| 2026-04-24 ~01:41 | Live spike: 49.7% PSI during investigation |
| 2026-04-24 ~02:51 | Manual master1 reboot triggered cascade |
| 2026-04-24 ~03:00 | Full cascade — 40-67% PSI sustained 40+ min |
| 2026-04-24 ~04:30 | Scale-to-0 recovery procedure executed |
| 2026-04-24 ~05:00 | Sequential reintroduction — cluster stable |
| 2026-04-24 ~06:00 | CPU stress test — 80% host CPU, 0% IO spike |
| 2026-04-24 ~06:30 | LIST spam test — 36% CPU, 57% IO spike |
| 2026-04-24 ~07:00 | Write storm test — single VM crashes entire host IO |
| 2026-04-24 ~07:30 | Root cause confirmed |

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

# Step 3: Theory elimination

I tested 12 theories over ~6 hours. 10 eliminated, 2 confirmed.

| # | Theory | Time | Verdict | Why eliminated |
|---|--------|------|---------|----------------|
| 1 | Lid switch / logind suspend storm | 45 min | Symptom only | Logind bursts are a MARKER of IO stall (timers queue during stall, fire at once when unblocked), not cause. A few hundred log lines can't generate 49% PSI. |
| 2 | Disk hardware failure | 30 min | Ruled out | SMART healthy, no IO errors in kernel logs, no blocked tasks. Hardware fine — the issue was how it was being used. |
| 3 | Kernel bug | 15 min | Ruled out | No oopses, no BUGs, no MCEs, no soft lockups, no call traces. |
| 4 | ZFS issue | 10 min | Ruled out | No ZFS pools exist. Storage is LVM-thin on NVMe, not ZFS. ZFS module loaded (PVE default) but unused. |
| 5 | qemu-ga occurrence #4 (TS-K8S-038) | 45 min | Ruled out for this event | qemu-ga at 0% CPU (not 98% like real occurrences). etcd slow 7 min BEFORE qemu-ga gap — causality reversed. |
| 6 | Host storage stall | 20 min | Ruled out | No LVM-thin metadata stall evidence. |
| 7 | VM memory starvation | 20 min | Contributor | VMs tight on RAM but not causal alone. |
| 8 | Host RAM overcommit | 15 min | Contributor | 24 GB allocated on 22 GB host, KSM active. Contributes but doesn't trigger. |
| 9 | SSSD restart cascade | 20 min | Ruled out | sssd was down from start of day. Static state, no cascade trigger. |
| 10 | Prometheus scrape storm | 25 min | Ruled out | Prometheus scraping failing endpoints generates API calls but not enough to saturate NVMe alone. |
| 11a | CPU stress causes cascade | 30 min | **Ruled out** | 80% host CPU on all 3 masters = 0% IO spike. Linux CPU scheduler distributes fairly. |
| 11b | IO/request spam causes cascade | 30 min | **CONFIRMED** | 100x concurrent LIST = instant 57% IO spike, 1343ms NVMe latency. |
| 12 | No IO isolation architecture | 20 min | **CONFIRMED** | Single VM write storm = host-wide IO stall. Zero per-VM IO QoS. |

Theory 5 deserves extra detail because I was initially wrong about it. I declared
"this is definitely TS-K8S-038 occurrence #4" with too much confidence. The timeline
proved causality was reversed:

```
22:26:15 UTC  FIRST etcd slow-apply warnings (1.15s delays)
22:31:07 UTC  ReadIndex timeout
22:33:03 UTC  qemu-ga LAST ping before gap  ← 7 MINUTES AFTER etcd trouble started
22:38:30 UTC  qemu-ga resumes
```

The qemu-ga gap was a SYMPTOM of the VM being IO-starved, not the cause. In the real
TS-K8S-038 events, qemu-ga was at 98% CPU with strace showing `write() = -1 EAGAIN`.
Here it was at 0%. Different failure mode, similar-looking symptoms.

# Step 4: Architecture — the actual problem

```
Physical Host: ASUS Laptop
├── AMD Ryzen 7 7730U (8 cores / 16 threads)
├── 22 GB RAM (DDR4)
├── Single 476.9 GB Consumer NVMe
│
└── Storage Layout:
    ┌──────────────────────────────────────────────────┐
    │          Single NVMe (nvme0n1)                   │
    │                   │                              │
    │          LVM-thin pool (local-lvm)               │
    │                   │                              │
    │    ┌──────────────┼──────────────┐               │
    │    │              │              │               │
    │  Masters(×3)  Workers(×3)  Other VMs(6+)        │
    │  dm-23,24,25  dm-26,27,28  dm-29,30,...         │
    │                                                  │
    │  ALL sharing ONE NVMe IO queue                   │
    │  ALL IO throttles = UNLIMITED                    │
    │  ZERO per-VM bandwidth/IOPS limits               │
    │  NO IO QoS of any kind                           │
    └──────────────────────────────────────────────────┘
```

15+ VM disks compete for the same single NVMe queue. Any VM that generates heavy IO
(intentionally or via cascade) starves ALL other VMs. Not a bug — an unconfigured default.

# Step 5: The cascade loop

```
┌─────────────────────────────────────────────────────────────┐
│                    THE CASCADE LOOP                          │
│                                                             │
│  TRIGGER (anything: OOM, qemu-ga, network blip, backup)    │
│       │                                                     │
│       ▼                                                     │
│  Controllers restart on affected master(s)                  │
│       │                                                     │
│       ▼                                                     │
│  Each restart → full LIST operation against apiserver        │
│       │                                                     │
│       ▼                                                     │
│  Apiserver forwards LIST to etcd (range reads)              │
│       │                                                     │
│       ▼                                                     │
│  3 etcds doing massive reads + fsync on SAME NVMe           │
│       │                                                     │
│       ▼                                                     │
│  NVMe saturates: latency 3ms → 1343ms (400x increase!)     │
│  Queue depth: normal → 700+ operations queued               │
│       │                                                     │
│       ▼                                                     │
│  ALL VMs starved of IO (shared queue, no isolation)          │
│       │                                                     │
│       ▼                                                     │
│  Liveness probes fail (can't reach apiserver in time)        │
│       │                                                     │
│       ▼                                                     │
│  MORE controllers restart → MORE LIST storms                 │
│       │                                                     │
│       └──────────── LOOP BACK TO TOP ────────────────────── │
│                                                             │
│  Self-sustaining until external intervention                 │
└─────────────────────────────────────────────────────────────┘
```

The cluster naturally produces this kind of request spam when:
- Multiple controllers restart simultaneously (each does full LIST on startup)
- Flux reconciles many kustomizations at once
- Watch connections disconnect and reconnect (forces full resync LIST)
- Post-cascade recovery (everything restarting at once = worst case)

# Step 6: Why it worked for weeks then failed

The cluster has a normal operating envelope where baseline load fits within NVMe capacity.
Day-to-day, minor perturbations happen but are absorbed because there's enough headroom.

What pushed it over on 2026-04-23/24 was multiple factors stacking:

| Factor | Impact |
|--------|--------|
| Backup ran ~10 hours before | Confirmed 40% IO impact during vzdump (TS-PVE-015) |
| Cluster limping all day | Unknown duration of degraded state |
| sssd not up from start of day | Possible cert/domain client issues |
| master1 hung silently for hours | Cluster running 2-master degraded, etcd quorum stressed |
| Manual master1 reboot at 02:51 | etcd had to resync hours of writes + full LIST load |

Each factor alone wouldn't trigger cascade. All of them stacking pushed past the
tipping point. Once the cascade started, it self-sustained.

# Step 7: Reproduction evidence — the definitive proof

## CPU stress test (all 3 masters, simultaneously)

```bash
# Run on each master:
for i in 1 2 3 4; do yes > /dev/null & done
```

Result:
```
CPU usage: 80.46% of 16 CPU(s)
Load average: 8.17, 4.78, 3.31
IO Pressure: ~0%  ← ZERO IO SPIKE
```

etcd still at 4.7% CPU. kube-apiserver still at 4.0%. kubelet at 1.7%. Linux CPU
scheduler fairly shared CPU between stress and control plane. Everything kept running.

**No cascade. No host IO spike. No cluster degradation.**

## LIST operation spam (all 3 masters, simultaneously)

```bash
# Run on each master:
for i in {1..100}; do
  kubectl get pods -A --output=json > /dev/null &
  kubectl get events -A --output=json > /dev/null &
done
```

Result:
```
CPU usage: 35.91% of 16 CPU(s)     ← MODERATE (less than CPU stress test!)
Load average: 32.99, 16.10, 8.07   ← HUGE
IO delay: 57.58%                    ← MASSIVE SPIKE
```

```
Device     r/s     rkB/s    r_await   aqu-sz    %util
dm-23      198.50  12922    1312.43   260.52    100%    ← master1
dm-24      150.50   9582    1496.95   225.29    100%    ← master2
dm-25      151.50   6432    1239.59   187.80    100%    ← master3
nvme0n1    508.50  29018    1343.14   685.82    90.55%
```

NVMe read latency: 1343ms (1.3 SECONDS per read, vs 1-3ms normal — 400x increase).
Queue depth: 700 operations queued. Disk utilization: 90-100% on all master devices.

**Instant cascade. Host unresponsive.**

## Configmap write storm (single VM only)

```bash
# From ONE master:
for i in {1..1000}; do
  kubectl create configmap stress-test-$i \
    --from-literal=data="$(head -c 10000 /dev/urandom | base64)" &
done
```

Result:
```
IO delay: 57.20%
NVMe latency: 302ms (100x increase from baseline)
Queue depth: 191
```

Apiserver unreachable from other masters. SSH hanging. VNC unresponsive. One VM
monopolizing the disk — OTHER VMs degraded too (dm-23 showed 302ms await and it
wasn't even the source VM).

This command on only 1 node was enough to break all SSH, make VNC unresponsive, rise
Proxmox to 50+ delay IO on the whole server level. Which makes a complete picture
that even if qemu ran against 1 node, only one node, and overwhelm it with IO, it
completely overwhelms the whole cluster and the whole server physical. There is no
actually isolation — 1 node crash can kill the server, not just the node.

## The definitive comparison

| Metric | CPU Stress (all 3) | LIST Spam (all 3) | Write Storm (1 VM) |
|--------|-------------------|-------------------|-------------------|
| Host CPU | 80.46% | 35.91% | 35.91% |
| IO PSI | ~0% | 57.58% | 57.20% |
| NVMe Latency | 1-3ms | 1343ms | 302ms |
| Queue Depth | normal | 700+ | 191 |
| Cluster OK? | YES | NO | NO |
| SSH OK? | YES | NO | NO |
| Cascade? | NO | YES | YES |

CPU stress used MORE CPU (80%) but caused ZERO IO problems.
Request spam used LESS CPU (36%) but caused CATASTROPHIC IO problems.

The mechanism is IO contention through etcd fsync/reads on shared NVMe, NOT CPU
starvation. This is why per-VM IO throttling is the fix, not CPU limits or memory.

# Step 8: Break-glass recovery (tested and validated)

When the cascade is active (PSI >30% sustained, multiple CrashLoopBackOff, restart
counts growing), this is the only reliable recovery:

**DO NOT reboot VMs** — creates a boot storm that adds MORE IO load. During the
incident, rebooting all VMs while degraded produced 49-67% sustained PSI for 40+ min.
The same reboot on a healthy cluster produced only 30% for 3 minutes.

**DO NOT drain nodes** — eviction generates API calls that feed the cascade.

## Scale-down order

```bash
# 1. Apps
kubectl -n apps scale deployment --all --replicas=0
kubectl -n database scale statefulset mariadb --replicas=0

# 2. Flux (CRITICAL — prevents reconciliation reverting your changes)
kubectl -n flux-system scale deployment --all --replicas=0

# 3. Monitoring
kubectl -n monitoring scale deployment --all --replicas=0
kubectl -n monitoring scale statefulset --all --replicas=0

# 4. DaemonSets (can't scale to 0 — use nodeSelector trick)
kubectl -n monitoring patch daemonset promtail \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"disabled":"true"}}}}}'
kubectl -n monitoring patch daemonset kube-prometheus-stack-prometheus-node-exporter \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"disabled":"true"}}}}}'

# 5. Remediation controller
kubectl -n remediation scale deployment --all --replicas=0

# 6. Wait 15-20 min for IO pressure to drop to baseline
watch -n 5 'cat /proc/pressure/io'
# Target: PSI drops below 5% and stays there
```

## Sequential reintroduction (validated order)

Bring back one at a time with 5-minute waits. This exact order was validated during
the 2026-04-24 incident — every component started with 0 restarts.

1. Prometheus (need visibility first)
2. Grafana (dashboards)
3. Loki (log storage)
4. Node-exporter (revert daemonset `nodeSelector`)
5. Promtail — this was the one I expected to tip things over. Previously had 14+
   restarts during cascade. Started in 14 seconds with 0 restarts. "They was never
   that fast" — because the cluster was healthy this time.
6. kube-state-metrics — previously 13+ restarts in CrashLoopBackOff. Now clean.
7. prometheus-operator
8. Alertmanager
9. MariaDB
10. WordPress
11. Flux controllers (LAST — will reconcile everything to git state)

Before starting Flux, consider suspending kustomizations first:
```bash
kubectl get kustomization -A -o name | \
  xargs -I {} kubectl patch {} -n flux-system --type=merge \
  -p '{"spec":{"suspend":true}}'
```

## What this proved

1. The cluster CAN run all workloads stably on current hardware
2. The cluster CANNOT recover from cascade on its own
3. Sequential startup with 5-min waits prevents cascade re-ignition
4. Same reboot on healthy vs degraded cluster = completely different outcome

# Step 9: Gotchas discovered during recovery

**Cannot scale daemonsets directly.** `kubectl scale daemonset --replicas=0` doesn't
work. Use the `nodeSelector` trick to make pods unschedulable.

**Flux fights manual scaling.** Flux will revert manual scaling to match git state.
Scale down Flux BEFORE other workloads.

**Remediation controller auto-recovery.** The remediation pod may automatically bring
back nodes you excluded. Worker3 came back up during recovery without being asked.

**etcd v3.6 env conflicts.** `ETCDCTL_ENDPOINTS` + `--endpoints` flag = fatal error.
`ETCDCTL_API=3` is unrecognized in v3.6 (harmless warning). Use either env vars or
flags, not both.

_____________________________________________________________________

[Final Root Cause]

CONFIRMED (2026-04-24, 8-hour investigation).

Zero IO isolation on shared consumer NVMe combined with Kubernetes cascade dynamics.
Single 476.9GB NVMe with LVM-thin pool, 15+ VM disks, ALL Proxmox IO throttles set
to unlimited. Any single VM can monopolize the entire NVMe queue, starving all other
VMs and triggering a self-sustaining cascade (probe failures → restarts → LIST storms
→ etcd IO → more probe failures → loop).

Empirically proven:
- CPU stress on all 3 masters (80% host CPU) = 0% IO spike
- LIST operation spam (100x concurrent) = instant 57% IO spike, 1343ms NVMe latency
- Single VM configmap write storm = host-wide IO delay, all SSH/VNC unresponsive

qemu-ga (TS-K8S-038) ruled out as direct cause for this occurrence (0% CPU, etcd
slow 7 min before qemu-ga gap). Remains a potential indirect trigger for future events.

## Architectural truths

**IO has no fair scheduler in this configuration.** Linux's CPU scheduler fairly
distributes CPU time — even at 80% host CPU, etcd still got 4.7%, apiserver 4.0%,
kubelet 1.7%. But IO has no per-VM QoS. When one VM floods the NVMe queue, ALL VMs
wait. One VM's storm = every VM's storm.

**The cascade is self-sustaining.** Once started, probes keep firing, restarts keep
LISTing, LISTs keep hitting etcd, etcd keeps queuing on the saturated NVMe. The only
break-glass is scale-to-0, wait for silence, then iterative restart with gaps.

**Multiple triggers converge on the same bottleneck:**

| Trigger | Path to Cascade |
|---------|----------------|
| qemu-ga busy loop (TS-K8S-038) | CPU spike → pod restarts → LIST storms → IO saturation |
| Backup IO (TS-PVE-015/020) | vzdump+zstd → NVMe saturation → VMs starved → probes fail |
| Flux retry storm (TS-K8S-042) | Tight retry loop → API hammering → etcd IO → cascade |
| Worker OOM (TS-K8S-030) | OOM kill → pod reschedule → LIST operations → IO pressure |
| Master hang (this incident) | Degraded quorum → reboot → etcd resync + full LIST → cascade |

The fix for ALL of these is the same: per-VM IO throttling prevents any single VM
from monopolizing the shared NVMe queue.

## My own summary

All IO is shared. One qemu or anything that causes high IO on one node loop can cause
all cluster + all Proxmox to be overwhelmed, and IO delay spikes.

There is no isolation on IO level since we share the disk.

The loop cannot be solved once created unless you do a clean silence and iterative
start — as I did when I set replicas to 0.

The qemu issue on kernel level I didn't figure out its root cause. But such IO crises
cause everything to hang and create incremental spikes that overwhelm the API which
restarted over 100 times + etcd, and damage internal components, overwhelm workers and
apps. Combine with proper readiness probe tuning.

When you consider that 10 hours before, the backup ran and I recorded the impact — 40%
IO delay on dev server — you can also see the keep crashing which was on the environment
from the beginning of the day. Combined with some services not being up like sssd from
the beginning. Suspect the environment might have faced issues with related cert
operations or was impacted by domain client issues. Nobody knows, but the main thing is
that every possible cause combined, which cost me 7 hours overnight to test and isolate,
to reach the root cause and be able to reproduce the issue with the IO test — not the
CPU test.

The complete story. Al hamdllah.

_____________________________________________________________________

[Final Solution]

## Immediate (this occurrence)

Rebooted Proxmox host. After reboot all VMs started normally, K8s cluster recovered.

## Primary fix: per-VM IO throttling (APPLIED)

Applied via Terraform on all k8s VMs (masters + workers) in both dev and prod:

```hcl
# terraform/dev/proxmox/vms/k8s_workers/main.tf (and masters)
disk {
  # ...existing config...

  speed {
    iops_read           = 500
    iops_read_burstable = 1500
    iops_write          = 300
    iops_write_burstable = 800
    read                = 30
    read_burstable      = 80
    write               = 20
    write_burstable     = 40
  }
}
```

This prevents any single VM from monopolizing the NVMe. The source VM chokes on its
own IO while the host and other VMs stay responsive.

## Automated safety net: IO storm watchdog (DEPLOYED on dev)

Bash script running on pve-dev via `@reboot` cron. Two detection rules:

- **Rule 1 (3+ victims):** if 3+ VMs show elevated IO pressure, find the source
  by CPU+IO fingerprint (source: low IO + high CPU; victims: high IO + low CPU).
  Reset the source VM.
- **Rule 2 (single stuck VM):** if one VM sustains >300% CPU for 2+ minutes, reset it.

Includes cooldown period and email alerts on both action and recovery.
See: `proxmox/disaster_recovery/io-storm/`

## Remediation pod hardened (dev only)

Dev remediation runs with a 3-minute confirmation delay before acting on NotReady
nodes. This prevents false triggers from IO storms where nodes appear disconnected but
are actually just IO-starved. Restore step removed on dev (restore is itself IO-heavy
on weak hardware). See: `kubernetes/dev/deployments/apps/remediation/DESIGN.md`

## Staged hardening (planned, not yet applied)

| Priority | Mitigation | Status |
|----------|-----------|--------|
| 1 | Per-VM IO throttling | **DONE** (Terraform) |
| 2 | IO storm watchdog | **DONE** (pve-dev) |
| 3 | Remediation confirmation delay | **DONE** (dev) |
| 4 | Probe timeout tuning (30s timeout, 6 failure threshold) | Planned |
| 5 | API server request limits (--max-requests-inflight=200) | Planned |
| 6 | Monitoring footprint reduction (dev) | Planned |
| 7 | Separate NVMe for etcd (hardware) | Future |

_____________________________________________________________________

[Risk Level] MEDIUM (was HIGH — IO throttling now applied)

Primary fix deployed via Terraform. IO storm watchdog active on dev. Remediation
hardened with confirmation delay. Remaining risk is probe timeout tuning (cascade
amplifier not yet dampened) and the qemu-ga kernel-level root cause (TS-K8S-038)
still unresolved.

_____________________________________________________________________

[References]

- TS-K8S-038 — qemu-ga EAGAIN busy loop (potential indirect trigger, not direct cause here)
- TS-K8S-042 — Flux retry storm (same cascade pattern, different trigger)
- TS-K8S-043 — NoExecute taint not applied (DR testing preceded this incident)
- TS-K8S-030 — Worker3 memory exhaustion (contributor to cascade risk)
- TS-PVE-015 — vzdump thermal shutdown during backup (same architectural weakness, 40% IO + thermal spike)
- TS-PVE-020 — vzdump backup destabilizes k8s cluster (k8s nodes excluded from dev backup)
- proxmox/disaster_recovery/io-storm/ — IO storm watchdog script and docs
- kubernetes/dev/deployments/apps/remediation/DESIGN.md — remediation confirmation delay reasoning
- terraform/dev/proxmox/vms/k8s_workers/main.tf — IO throttle values in Terraform
