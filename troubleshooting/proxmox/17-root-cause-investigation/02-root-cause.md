# TS-PVE-017 Root Cause Analysis — CONFIRMED

**Date**: 2026-04-24
**Status**: ROOT CAUSE CONFIRMED via empirical reproduction
**Investigator**: Sabry (8-hour overnight investigation)

_____________________________________________________________________

## Root Cause (One Statement)

Zero IO isolation on a shared consumer NVMe — single drive, LVM-thin pool, 15+ VM disks, ALL Proxmox IO throttles unlimited — combined with Kubernetes cascade dynamics creates self-sustaining IO storms from any trigger that saturates the disk queue.

_____________________________________________________________________

## Architecture Diagram

```
Physical Host: ASUS Laptop
├── AMD Ryzen 7 7730U (8 cores / 16 threads)
├── 22 GB RAM (DDR4)
├── Single 476.9 GB Consumer NVMe (Samsung/equivalent)
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

**15+ VM disks** compete for the same single NVMe queue. Any VM that generates heavy IO (intentionally or via cascade) starves ALL other VMs.

_____________________________________________________________________

## The Hardware

| Component | Spec |
|-----------|------|
| Host | ASUS laptop |
| CPU | AMD Ryzen 7 7730U (8c/16t) |
| RAM | 22 GB (DDR4) |
| Storage | Single 476.9 GB consumer NVMe |
| K8s Masters | 3x VMs (1010, 1011, 1012) — 3 GB each |
| K8s Workers | 3x VMs (1020, 1021, 1022) — 3 GB / 3 GB / 2.75 GB |
| Other VMs | FreeIPA, vault×3, ansible, local-runner, templates |
| LXCs | 6 containers |
| Total VM memory | ~24 GB allocated on 22 GB host (overcommitted) |
| Storage backend | LVM-thin pool, all disks unlimited IO |

_____________________________________________________________________

## The Cascade Loop Mechanism

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
│  Liveness probes fail (HTTP to apiserver, which is blocked)  │
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
- Prometheus scraping during controller churn
- Watch connections disconnect and reconnect (forces full resync LIST)
- Post-cascade recovery (everything restarting at once)

_____________________________________________________________________

## Why It Worked for Weeks Then Failed

The cluster has a normal operating envelope where baseline load fits within NVMe capacity. Day-to-day, minor perturbations happen but are absorbed because the system has enough headroom.

What pushed it over on 2026-04-23/24 was multiple factors stacking:

| Factor | When | Impact |
|--------|------|--------|
| Backup ran | ~10 hours before incident | Confirmed 40% IO impact on dev during backup (vzdump + zstd compression) |
| Cluster limping | All day before investigation | Unknown duration of degraded state |
| sssd not up | From start of day | Possible cert operation or domain client issue |
| master1 hung silently | Hours before 02:51 reboot | Cluster running 2-master degraded mode, etcd quorum stressed |
| Manual master1 reboot | 02:51 | etcd had to resync hours of writes, apiserver faced full scrape/LIST load, probes fired before stable |

Each factor alone wouldn't trigger cascade. All of them stacking pushed the cluster past its tipping point. Once the cascade started, it self-sustained.

I investigated why "it worked for weeks" because that question reframed the entire problem. The hardware hadn't changed. The config hadn't changed. Something specific happened TODAY — and it was the compound stacking of these factors, all landing on an architecture with zero IO isolation.

_____________________________________________________________________

## Why CPU Stress Alone Doesn't Trigger It

I proved this empirically. CPU stress test on ALL 3 masters simultaneously:

```
CPU usage: 80.46% of 16 CPU(s)
Load average: 8.17, 4.78, 3.31
IO Pressure: ~0%  ← ZERO IO SPIKE
```

Linux's CPU scheduler fairly distributes CPU time. Even at 80% host CPU, etcd still got 4.7% CPU, apiserver got 4.0%, kubelet got 1.7%. Everything kept running.

But IO has no fair scheduler in this configuration. When one VM floods the NVMe queue, ALL VMs wait. There's no per-VM IO QoS — the NVMe processes requests in queue order regardless of which VM submitted them. One VM's storm = every VM's storm.

This is why qemu-ga's CPU busy loop (TS-K8S-038) doesn't directly cause the cascade through CPU starvation. It can only trigger it indirectly: qemu-ga pegs CPU → VM briefly unresponsive → kubelet marks pods unhealthy → pods restart → restart = full LIST → IO storm → cascade. The path goes through IO, not CPU.

_____________________________________________________________________

## The Architectural Truths

These are the fundamental facts I confirmed through the investigation:

### Architecture truth
Single NVMe, LVM-thin, zero IO isolation. Every VM shares one queue. Whatever monopolizes the queue monopolizes the host. Not a bug — an unconfigured default.

### Cascade truth
Any trigger that creates heavy IO on any one node can overwhelm everything. Once the loop starts, it can't self-heal — probes keep firing, restarts keep LISTing, LISTs keep hitting etcd, etcd keeps queuing on the saturated NVMe. The only break-glass is `scale --replicas=0` on workloads, wait for silence, then iterative restart with gaps.

### Trigger truth
The qemu-ga kernel-level root cause from TS-K8S-038 is still not solved. I didn't fix it during this investigation — I just identified that its symptoms get amplified by the IO architecture. Once qemu-ga (or anything else) stresses a master, probe failures cascade → apiserver gets pounded → 100+ restarts → etcd strained → workers feel it → apps crash → probe readiness compounds it.

_____________________________________________________________________

## My Own Summary

All IO is shared. One qemu or anything that causes high IO on one node loop can cause all cluster + all Proxmox to be overwhelmed, and IO delay spikes.

There is no isolation on IO level since we share the disk.

The loop cannot be solved once created unless you do a clean silence and iterative start — as I did when I set replicas to 0.

The qemu issue on kernel level I didn't figure out its root cause. But such IO crises cause everything to hang and create incremental spikes that overwhelm the API which restarted over 100 times + etcd, and damage internal components, overwhelm workers and apps. Combine with proper readiness probe tuning.

When you consider that 10 hours before, the backup ran and I recorded the impact — 40% IO delay on dev server — you can also see the keep crashing which was on the environment from the beginning of the day. Combined with some services not being up like sssd from the beginning. Suspect the environment might have faced issues with related cert operations or was impacted by domain client issues. Nobody knows, but the main thing is that every possible cause combined, which cost me 7 hours overnight to test and isolate, to reach the root cause and be able to reproduce the issue with the IO test — not the CPU test.

The complete story. Al hamdllah.

_____________________________________________________________________

## The Fix

**Primary**: Per-VM IO throttling via Proxmox Hardware → Disk → Bandwidth tab (or `qm set` with `mbps_rd`, `mbps_wr`, `iops_rd`, `iops_wr` parameters). Prevents any single VM from monopolizing the NVMe.

**Validation**: Re-run the configmap write storm test with throttles applied. Expected result: source VM chokes on its own IO, host and other VMs stay responsive.

**Long-term**: Separate NVMe for etcd data directories, or upgrade to hardware with multiple storage devices.

See [05-remediation-stages.md](05-remediation-stages.md) for the full staged implementation plan.
