# TS-PVE-022 | 2026-05-03 | OPEN | IMPROVEMENT
_____________________________________________________________________

[Info]
Domain: Proxmox / Monitoring / Automation
Sub-techs: Proxmox API, Python, VM memory metrics, IO storm watchdog
Environment: dev + prod
Re-opened: No

_____________________________________________________________________

[Issue Description]
Discovered during DR test: worker-disk-full-root-filesystem (2026-05-03).

During the disk pressure test, Proxmox showed worker3 memory at 98.23%
(6.88 GiB of 7.00 GiB) while disk was at 96%. Disk pressure cascaded
into memory pressure — the two compound each other.

Currently have an IO storm watchdog script on pve-dev that detects IO
cascade sources or stuck CPU VMs and auto-resets them. Need a similar
script for memory — detect when a VM's memory usage (from Proxmox API,
not in-guest metrics) crosses a threshold.

The difference from the IO watchdog: memory is harder to act on safely.
Rebooting a VM with high memory might be the wrong call — the VM could
be doing legitimate work (compiling, caching, Java heap). Need to think
about what action is appropriate vs just alerting.

_____________________________________________________________________

[Analysis]

# Context from DR test:

Proxmox memory metric for worker3 during disk pressure:
  98.23% (6.88 GiB of 7.00 GiB)

This is the Proxmox API metric (qemu balloon driver), not in-guest
MemAvailable. As noted in TS-PVE-016, Proxmox counts Linux page cache
as "used" so the number looks worse than reality. But 98% is genuinely
high — this wasn't just cache.

# Existing IO storm watchdog:

Script runs on pve-dev, checks IO wait across VMs, identifies the source
of IO storms, auto-resets the offending VM, sends email alert + recovery
notification. This pattern works for IO because high IO + stuck VM is
almost always pathological.

# Memory is different:

High memory is NOT always a problem:
  - Java apps with large heaps (normal)
  - Linux page cache (misleading metric)
  - K8s worker running many pods (expected)
  - Compilation/build tasks (temporary)

High memory IS a problem when:
  - OOM killer fires (visible in dmesg)
  - VM becomes unresponsive (no qemu-ga heartbeat)
  - Memory + IO pressure compound (like in the DR test)

# What the script should do:

Phase 1 — Monitor and alert only (safe):
  - Poll Proxmox API for VM memory usage every 5 minutes
  - Alert (email) when any VM exceeds 90% for >10 minutes
  - Log history for trend analysis
  - NO automatic action

Phase 2 — Consider action (risky, needs design):
  - Only act if memory is high AND node is unresponsive
  - Coordinate with k8s remediation pod (don't double-act)
  - Consider: is Proxmox-layer reboot redundant if remediation pod
    already handles NotReady nodes?

_____________________________________________________________________

[Potential Solutions]

1. Python script on Proxmox host — poll API, email on threshold:
   Similar to IO storm watchdog. Runs via cron or systemd timer.
   Uses Proxmox API token (already exists for remediation pod).
   Alert-only, no auto-action.

2. Integrate into existing IO storm watchdog:
   Add memory check to the same script — one monitoring daemon instead
   of two. Risk: making the IO watchdog more complex.

3. Prometheus + node-exporter (already deployed):
   Could handle this entirely in Prometheus with MemAvailable metric.
   BUT: node-exporter gets evicted during pressure (TS-K8S-060), so
   the Proxmox-layer script would catch what Prometheus misses.

4. Defer to remediation pod:
   The k8s remediation pod already handles NotReady nodes. A Proxmox
   memory script would catch pre-NotReady degradation. Question is
   whether that early warning is worth a separate script.

_____________________________________________________________________

[Final Root Cause]
No Proxmox-layer memory monitoring exists. The IO storm watchdog covers
IO/CPU but memory pressure is invisible at the hypervisor layer until
the VM goes unresponsive.

_____________________________________________________________________

[Final Solution]
PENDING — need to design and implement Python script. Alert-only first,
auto-action deferred until the safety tradeoffs are understood.

_____________________________________________________________________

[Risk Level] LOW — memory pressure is already caught when it cascades
to NotReady (remediation pod) or when node-exporter reports it
(Prometheus). This is a defense-in-depth improvement, not a gap.

_____________________________________________________________________

[References]
- Source: disaster-recovery/worker-disk-full-root-filesystem.md (DR test 2026-05-03)
- Related: TS-PVE-016 (Proxmox memory metrics misleading — Linux cache counted as used)
- Related: TS-PVE-017 (IO storm watchdog — same monitoring pattern for IO/CPU)
- Related: TS-K8S-060 (monitoring gaps — node-exporter eviction blind spot)
- Code: proxmox/disaster_recovery/ (existing watchdog scripts)
