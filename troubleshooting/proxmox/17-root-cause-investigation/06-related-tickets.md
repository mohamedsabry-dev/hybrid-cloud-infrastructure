# TS-PVE-017 Related Tickets and Cross-References

**Purpose**: Map how TS-PVE-017 connects to other incidents and what this investigation proved about each relationship.

_____________________________________________________________________

## Relationship Map

```
                    ┌─────────────────────────────┐
                    │  ARCHITECTURAL WEAKNESS      │
                    │  Single NVMe, LVM-thin,      │
                    │  zero IO isolation            │
                    └──────────────┬───────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
              ▼                    ▼                    ▼
     TRIGGER events         AMPLIFIER              SAME PATTERN
     (push past             (makes it               (different
      tipping point)         self-sustaining)        trigger)
              │                    │                    │
    ┌─────────┤               ┌────┤              ┌────┤
    │         │               │    │              │    │
    ▼         ▼               ▼    ▼              ▼    ▼
 TS-K8S   TS-PVE          Probe   K8s         TS-K8S  TS-K8S
  -038     -015           timeouts restart      -042   -030
 qemu-ga  backup          (too    cascade       Flux   worker3
 CPU loop IO impact       short)  dynamics      storm  OOM
```

_____________________________________________________________________

## TS-K8S-038 — qemu-ga EAGAIN Busy Loop

**File**: `troubleshooting/kubernetes/38-qemu-guest-agent-cpu-loop.md`
**Relationship**: POTENTIAL TRIGGER (indirect, via IO — not direct via CPU)
**Status**: Root cause UNRESOLVED (kernel-level EAGAIN on virtio-serial)

### Connection to TS-PVE-017
The investigation RULED OUT qemu-ga as the direct cause of this specific occurrence:
- qemu-ga was at 0% CPU throughout (no strace evidence of EAGAIN loop)
- etcd slow-apply started 7 minutes BEFORE the qemu-ga ping gap
- Causality was reversed from the original TS-K8S-038 theory

However, the investigation confirmed qemu-ga remains a valid TRIGGER for future cascades:
- qemu-ga busy loop → VM briefly unresponsive → kubelet marks pods unhealthy → pods restart → restart = full LIST → IO storm → cascade
- The path goes through IO, not CPU starvation
- CPU stress test proved CPU alone doesn't trigger cascade
- TS-K8S-038 documented occurrences hit 2 masters simultaneously (Apr 17: master1+master3, Apr 18: master1+master2) — multi-master events are higher risk

### What this investigation adds to TS-K8S-038
The 3 documented occurrences in TS-K8S-038 (with captured strace evidence) remain legitimate qemu-ga events. Tonight's event was a different failure mode that produces similar-looking symptoms through IO cascade, not qemu-ga CPU loop.

_____________________________________________________________________

## TS-PVE-015 — Proxmox Crash During Backup

**File**: `troubleshooting/proxmox/15-proxmox-crash-during-backup-unknown-cause.md`
**Relationship**: CONTRIBUTOR to TS-PVE-017 incident + SAME ROOT CAUSE FAMILY
**Status**: Re-opened 2026-04-23, root cause updated to thermal (vzdump + zstd → 85-92C)

### Connection to TS-PVE-017
- Backup ran ~10 hours before the TS-PVE-017 incident
- During the investigation, I confirmed 40% IO delay on dev server during backup
- Same mechanism: vzdump + zstd compression saturates NVMe IO, starving VMs
- The backup's IO impact was one of the contributing factors that stacked to push the cluster past its tipping point on incident day
- K8s master CrashLoopBackOff during backup was documented in TS-PVE-015's re-opening (33-38% dev IO delay)

### Shared architectural weakness
Both TS-PVE-015 and TS-PVE-017 are downstream effects of the same problem: no IO isolation on shared NVMe. Backup saturates NVMe → VMs starved. Cascade saturates NVMe → VMs starved. Same bottleneck, different triggers.

_____________________________________________________________________

## TS-PVE-018 — Prod Server Complete Shutdown During Backup

**File**: `troubleshooting/proxmox/18-prod-server-complete-shutdown-during-backup.md`
**Relationship**: SAME ROOT CAUSE FAMILY (different symptom)
**Status**: RESOLVED — thermal shutdown from vzdump zstd compression

### Connection to TS-PVE-017
- Same underlying issue: backup operations overwhelming the host
- TS-PVE-018 manifested as thermal shutdown (temperature_monitor.sh triggered at 91C)
- TS-PVE-017 manifested as IO cascade (NVMe saturation from K8s restart storm)
- Different symptoms, same architectural weakness: single host doing everything with no resource isolation

_____________________________________________________________________

## TS-K8S-042 — Flux Retry Storm Cluster Outage

**File**: `troubleshooting/kubernetes/42-flux-retry-storm-cluster-outage.md`
**Relationship**: SAME CASCADE PATTERN (different trigger)
**Status**: RESOLVED

### Connection to TS-PVE-017
This incident exhibited the EXACT same cascade dynamics:
- Trigger: anti-affinity deadlock caused Grafana rollout to stick
- Flux retried the failed Helm upgrade in a tight loop
- Each retry hammered API servers with patch operations
- etcd destabilized, all 3 API servers went unhealthy
- Entire cluster became unresponsive
- Two nodes needed physical reboot

The TS-K8S-042 cascade was Flux-driven (tight retry loop → API hammering). The TS-PVE-017 cascade was restart-driven (probe failures → restarts → LIST storms). Both converge on the same bottleneck: etcd IO on shared NVMe.

### Lesson confirmed
TS-K8S-042 showed that Flux has no circuit breaker — it retries indefinitely without backoff. This is why Flux must be the LAST thing started during recovery (documented in 04-cascade-recovery.md), and why Flux should be suspended during incident response.

_____________________________________________________________________

## TS-K8S-043 — NoExecute Taint Not Applied

**File**: `troubleshooting/kubernetes/43-noexecute-taint-not-applied.md`
**Relationship**: CONTEXT (DR testing preceded TS-PVE-017)
**Status**: RESOLVED

### Connection to TS-PVE-017
- DR testing (multiple shutdown/start cycles) preceded the TS-PVE-017 incident
- TS-K8S-043 revealed PartialDisruption mode: Kubernetes rate-limits NoExecute taints when >55% of nodes fail simultaneously
- This means during cascade (when 2+ masters are struggling), K8s may NOT properly evict pods — compounding the problem
- Fixed with `--unhealthy-zone-threshold=0.8`

_____________________________________________________________________

## TS-K8S-030 — Worker3 Memory Exhaustion VM Crash

**File**: `troubleshooting/kubernetes/30-worker3-memory-exhaustion-vm-crash.md`
**Relationship**: CONTRIBUTOR (memory constraint increases cascade risk)
**Status**: RESOLVED (increased to 3.25GB, later adjusted during TS-PVE-017 session)

### Connection to TS-PVE-017
- Worker3 was at 2.75GB during the incident (crashed from memory exhaustion previously)
- Memory-constrained VMs are more likely to OOM → trigger cascade
- During the TS-PVE-017 investigation, worker3 came back via remediation controller at its original 2.75GB instead of the 3GB applied to workers 1 and 2
- Memory inconsistency flagged as action item in 05-remediation-stages.md

_____________________________________________________________________

## The Unified Theory

All these incidents share the same underlying architectural weakness:

**Single consumer NVMe → LVM-thin → 15+ VM disks → no IO QoS**

Different triggers converge on the same cascade mechanism:

| Trigger | Path to Cascade |
|---------|----------------|
| qemu-ga busy loop (TS-K8S-038) | CPU spike → pod restarts → LIST storms → IO saturation |
| Backup IO (TS-PVE-015/018) | vzdump+zstd → NVMe saturation → VMs starved → probe failures |
| Flux retry storm (TS-K8S-042) | Tight retry loop → API hammering → etcd IO → cascade |
| Worker OOM (TS-K8S-030) | OOM kill → pod reschedule → LIST operations → IO pressure |
| Master hang (TS-PVE-017 trigger) | Degraded quorum → reboot → etcd resync + full LIST → cascade |

The fix for ALL of these is the same: **per-VM IO throttling** prevents any single VM from monopolizing the shared NVMe queue.

_____________________________________________________________________

## What This Investigation Resolved vs What Remains Open

### Resolved
- Root cause MECHANISM: IO contention on shared NVMe + K8s cascade dynamics
- Recovery PROCEDURE: scale-to-0 + sequential reintroduction (tested and validated)
- Root cause of TS-PVE-017 specifically: compound stacking of backup IO + degraded cluster + master hang + no IO isolation
- Relationship between CPU stress and IO cascade: CPU alone doesn't trigger it (empirically proven)

### Remains Open
- qemu-ga kernel-level EAGAIN root cause (TS-K8S-038) — not solved, just identified as indirect trigger
- Why master1 hung silently for hours on incident day — previous-boot journal not reviewed
- IO throttling not yet applied — plan documented in 05-remediation-stages.md
- Whether per-VM IO throttling values are correctly balanced — requires validation testing
