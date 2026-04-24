# TS-PVE-017 Root Cause Investigation

**Ticket**: TS-PVE-017 — Proxmox Host CPU/IO Spike, VMs Stuck
**Date**: 2026-04-23/24 (overnight, ~8 hours)
**Status**: ROOT CAUSE CONFIRMED
**Investigator**: Sabry

## Root Cause (One Line)

Zero IO isolation on shared NVMe (single consumer drive, LVM-thin, all VM IO unlimited) combined with Kubernetes cascade dynamics creates self-sustaining IO storms from any trigger that saturates the disk queue.

## Files

| File | Purpose |
|------|---------|
| [01-investigation-timeline.md](01-investigation-timeline.md) | All 12 theories tested, with commands, outputs, and elimination reasoning |
| [02-root-cause.md](02-root-cause.md) | Confirmed root cause: IO architecture + cascade mechanism |
| [03-reproduction-evidence.md](03-reproduction-evidence.md) | CPU stress vs IO stress tests — the definitive proof |
| [04-cascade-recovery.md](04-cascade-recovery.md) | Break-glass recovery procedure (scale-to-0 + sequential reintroduction) |
| [05-remediation-stages.md](05-remediation-stages.md) | Staged fix plan: IO throttling, probe tuning, API limits |
| [06-related-tickets.md](06-related-tickets.md) | Cross-references to TS-K8S-038, TS-PVE-015, TS-K8S-042, etc. |

## Key Finding

CPU stress on all 3 masters (80% host CPU) = 0% IO spike.
LIST operation spam (100x concurrent) = instant 57% IO spike.
The mechanism is IO contention through etcd fsync on shared NVMe, not CPU starvation.

## Fix (Not Yet Applied)

Per-VM IO throttling via Proxmox Hardware -> Disk -> Bandwidth tab.
See [05-remediation-stages.md](05-remediation-stages.md) for staged implementation plan.
