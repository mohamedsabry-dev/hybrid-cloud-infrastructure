VMware Live Migration — vMotion Signal Flow (Summary Trace)
============================================================

pre-trace (one-time setup):
  vCenter cluster with 3 ESXi hosts, shared NFS storage
    → dedicated vMotion network (10.0.30.x/24) isolated from production
    → VMkernel adapters with vMotion enabled on each host

admin right-clicks VM → Migrate → selects destination host
  → vCenter pre-flight: memory available? vMotion network reachable? CPU compatible? shared storage accessible?
    → any check fails → migration blocked

cold migration path:
  VM powered off → disk on shared storage: pointer update only (no copy)
    → if local storage: full disk copy (Storage vMotion)
      → VM registered on destination → powered on → TCP connections lost

live migration (vMotion) path:
  → Phase 1: source ESXi copies ALL memory pages to destination over 10.0.30.x
    → VM keeps running, dirty pages tracked via bitmap
    → disk NOT transferred (shared NFS — both hosts see same .vmdk)

  → Phase 2: iterative dirty page copy
    → each iteration copies fewer pages (40% → 15% → 3%)
      → convergence: remaining set small enough for sub-100ms transfer

  → Phase 3: switchover (stun)
    → VM paused on source (<100ms)
      → final dirty pages + CPU register state transferred
        → VM resumes on destination → source memory released
          → TCP connections survive (same MAC, same IP)

→ memory ballooning impact (nested ESXi):
  → source nested ESXi does NOT release memory after VM migrated away
    → balloon driver sees "reserved" even though guest is gone
    → example: migrate 3 VMs from Production → Production still holds 18 GB (not 6 GB)
      → requires manual release, contributed to decision to abandon nested for physical Proxmox
  → does NOT happen on Proxmox (no balloon, dedicated allocation)

→ vCenter updates inventory → physical switch learns new port via RARP
  → storage unchanged (compute-only move, zero disk IO)

DRS (if enabled):
  → monitors CPU/memory balance → auto-triggers vMotion on imbalance
    → anti-pattern: thrashing when hosts equally loaded

→ vSphere HA (host failure response):
  → HA agents exchange heartbeats (network + datastore) across cluster
    → host stops responding → both heartbeats lost → confirmed dead
      → surviving hosts restart VMs in priority order (critical → normal → low)
        → admission control: reserved capacity must exist (3 hosts, tolerate 1 = 33% reserved)
  → isolation response: host loses network but VMs run → configurable (leave running / power off)
  → HA = reactive (restart dead VMs), DRS = proactive (rebalance running VMs)
  → Proxmox equivalent: none (single host per env, K8s rescheduling + remediation pod for node-level)
