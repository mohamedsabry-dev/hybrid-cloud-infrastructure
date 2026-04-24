# TS-PVE-017 Remediation Plan — Staged Implementation

**Status**: NOT YET APPLIED — this is the plan, not what was done
**Created**: 2026-04-24
**Context**: Root cause confirmed as zero IO isolation on shared NVMe + K8s cascade dynamics

_____________________________________________________________________

## Decision Reasoning

I chose a staged approach because of what I learned during the 7-hour investigation: parallel changes on constrained hardware cause exactly the cascade we're trying to prevent. Every stage validates before moving to the next. The IO throttling is the primary fix — everything else is resilience hardening.

The investigation proved that CPU stress (80% host CPU on all 3 masters) caused 0% IO spike, but a single VM's write storm caused host-wide IO delay. The fix must target IO isolation, not CPU or memory.

_____________________________________________________________________

## Stage 1: Memory Normalization (Immediate)

### Problem
Worker memory is inconsistent after the investigation session. Worker3 came back via the remediation controller at its original 2.75GB instead of the 3GB applied to workers 1 and 2.

### Current State
| VM | Role | Memory | Expected |
|----|------|--------|----------|
| 1010 | master1 | 3072 MB | OK |
| 1011 | master2 | 3072 MB | OK |
| 1012 | master3 | 3072 MB | OK |
| 1020 | worker1 | 3072 MB | OK (was 3328, reduced during session) |
| 1021 | worker2 | 3072 MB | OK (was 3328, reduced during session) |
| 1022 | worker3 | 2816 MB (2.75GB) | NEEDS UPDATE to 3072 |

### Commands
```bash
# Requires brief outage for worker3
qm shutdown 1022
qm set 1022 --memory 3072
qm start 1022

# Verify
qm config 1022 | grep memory
```

### Validation
```bash
kubectl get nodes
kubectl top nodes
# worker3 should show ~3GB allocatable
```

_____________________________________________________________________

## Stage 2: Per-VM IO Throttling (PRIMARY FIX)

### Why This Is the Fix

During the investigation, I discovered that ALL Proxmox IO throttle values were set to UNLIMITED. Found via Proxmox GUI: Hardware → scsi0 → Edit → Bandwidth tab — every field showed "unlimited."

This means any single VM can monopolize the entire NVMe bandwidth. The configmap write storm test proved it: 1000 configmaps from ONE VM caused host-wide IO delay, SSH unresponsive, and VNC frozen on ALL other VMs.

### Discovery Evidence (from Proxmox GUI screenshots during investigation)
- Read limit (MB/s): unlimited
- Write limit (MB/s): unlimited
- Read limit (ops/s): unlimited
- Write limit (ops/s): unlimited
- Read max burst (MB): default
- Write max burst (MB): default
- Read max burst (ops): default
- Write max burst (ops): default

### Proposed Throttle Values

Based on NVMe specs (~2000 MB/s sequential, ~50k IOPS random) and the need to prevent any single VM from saturating the queue:

**K8s Masters (VM 1010, 1011, 1012)**
| Parameter | Value | Rationale |
|-----------|-------|-----------|
| mbps_rd | 100 | Enough for etcd reads + apiserver |
| mbps_wr | 50 | etcd WAL fsync + log writes |
| iops_rd | 2000 | LIST operations, etcd range reads |
| iops_wr | 1000 | etcd commits, container logs |
| mbps_rd_max | 200 | 2x burst for startup/recovery |
| mbps_wr_max | 100 | 2x burst |
| iops_rd_max | 4000 | 2x burst |
| iops_wr_max | 2000 | 2x burst |

**K8s Workers (VM 1020, 1021, 1022)**
| Parameter | Value | Rationale |
|-----------|-------|-----------|
| mbps_rd | 200 | Application IO, image pulls |
| mbps_wr | 100 | Application writes, container logs |
| iops_rd | 3000 | Application random reads |
| iops_wr | 2000 | Application random writes |
| mbps_rd_max | 400 | 2x burst |
| mbps_wr_max | 200 | 2x burst |

**Non-critical VMs (FreeIPA, vault, ansible, templates)**
| Parameter | Value | Rationale |
|-----------|-------|-----------|
| mbps_rd | 50 | Light workloads |
| mbps_wr | 25 | Light workloads |
| iops_rd | 1000 | Minimal random IO |
| iops_wr | 500 | Minimal random IO |

### Application Methods

**Method A: Via Proxmox GUI (recommended for first VM)**
1. Select VM → Hardware → scsi0 → Edit → Bandwidth tab
2. Fill in the values from the table above
3. Click OK
4. Applies immediately — no reboot needed

**Method B: Via CLI (faster for batch application)**

```bash
# Masters
for vmid in 1010 1011 1012; do
  qm set $vmid -scsi0 local-lvm:vm-${vmid}-disk-0,\
aio=io_uring,backup=1,cache=none,discard=on,iothread=0,\
replicate=1,size=25G,ssd=1,\
mbps_rd=100,mbps_wr=50,\
iops_rd=2000,iops_wr=1000,\
mbps_rd_max=200,mbps_wr_max=100,\
iops_rd_max=4000,iops_wr_max=2000
done

# Workers
for vmid in 1020 1021 1022; do
  qm set $vmid -scsi0 local-lvm:vm-${vmid}-disk-0,\
aio=io_uring,backup=1,cache=none,discard=on,iothread=0,\
replicate=1,size=25G,ssd=1,\
mbps_rd=200,mbps_wr=100,\
iops_rd=3000,iops_wr=2000,\
mbps_rd_max=400,mbps_wr_max=200
done
```

**Verify applied:**
```bash
qm config 1010 | grep scsi0
```

### Implementation Order
1. Apply throttle to worker3 first (least critical)
2. Observe 1 hour — monitor PSI, check no baseline degradation
3. Apply to workers 1 and 2
4. Apply to masters one at a time with 5-min gaps
5. Apply to non-critical VMs

### IO Thread Consideration
During the investigation, the Proxmox disk settings showed "IO thread: unchecked". Enabling iothread gives each virtio disk its own processing thread, improving IO parallelism. However, this requires a VM stop/start (not live-applicable like throttle limits). Consider enabling during a maintenance window:

```bash
qm set 1010 --scsi0 local-lvm:vm-1010-disk-0,iothread=1,...
# Requires VM restart to take effect
```

_____________________________________________________________________

## Stage 3: Validate IO Throttling (Reproduction Tests)

### Purpose
Re-run the same tests that proved the root cause, now with throttles applied. The source VM should choke on its own IO while the host and other VMs stay responsive.

### Test 1: Configmap write storm (single VM)
```bash
# From ONE master (the one with throttle applied)
for i in {1..1000}; do
  kubectl create configmap stress-test-$i \
    --from-literal=data="$(head -c 10000 /dev/urandom | base64)" &
done
```

**Expected WITHOUT throttle** (proven during investigation):
- Host IO delay: 57%+
- NVMe latency: 302-1343ms
- SSH to all VMs unresponsive
- Queue depth: 191-700

**Expected WITH throttle**:
- Source VM's IO queue builds up (throttled)
- Host IO delay stays <20%
- Other VMs remain responsive via SSH
- NVMe latency stays <50ms for other VMs

From the rootcause theory: "Apply the per-VM IO throttle when you wake up, rerun the configmap spam test, and you should see the host stay responsive while the source VM chokes on its own rope. That'll be the final proof."

### Test 2: LIST operation spam
```bash
# From ONE master
for i in {1..100}; do
  kubectl get pods -A --output=json > /dev/null &
  kubectl get events -A --output=json > /dev/null &
done
```

**Expected WITH throttle**:
- Source VM hits its IOPS limit
- kubectl commands queue inside the VM
- Host PSI stays <15%
- Other masters' etcd remains responsive

### Cleanup after tests
```bash
kubectl delete configmap -l app!=important --field-selector metadata.name=stress-test-*
# Or
for i in {1..1000}; do kubectl delete configmap stress-test-$i 2>/dev/null; done
```

### If throttle values are too restrictive
Signs: baseline cluster operations become slow, probes start failing under normal load, etcd slow-apply warnings in steady state.

Fix: increase limits by 50%, re-validate. The goal is preventing runaway, not constraining normal operation.

### If throttle values are too permissive
Signs: reproduction test still causes host-wide IO delay >30%.

Fix: reduce limits by 25%, re-test. Focus on iops_wr (write IOPS) first — etcd fsyncs are the primary cascade driver.

### Rollback
```bash
# Remove all throttle parameters (back to unlimited)
qm set <VMID> -scsi0 local-lvm:vm-<VMID>-disk-0,\
aio=io_uring,backup=1,cache=none,discard=on,iothread=0,\
replicate=1,size=25G,ssd=1
```

_____________________________________________________________________

## Stage 4: Probe Timeout Tuning

### Why
Default liveness probe timeouts (1-5 seconds) work on beefy hardware but fail catastrophically on constrained hardware. Probe failures are the CASCADE AMPLIFIER — if probes are more tolerant, the cascade is harder to trigger.

During the investigation, I observed that probe timeouts were causing the restart storm. Each failed probe → restart → LIST operation → more IO → more failed probes.

### Suggested values for constrained hardware

```yaml
livenessProbe:
  timeoutSeconds: 30    # was 1-5
  periodSeconds: 30     # was 10
  failureThreshold: 6   # was 3
```

### For kubeadm static pods (edit on each master)
```bash
# Files to modify:
/etc/kubernetes/manifests/kube-apiserver.yaml
/etc/kubernetes/manifests/kube-scheduler.yaml
/etc/kubernetes/manifests/kube-controller-manager.yaml
/etc/kubernetes/manifests/etcd.yaml
```

Changes apply automatically when kubelet detects the file modification.

### For DaemonSets and Deployments (Flux-managed)
```bash
kubectl -n kube-system patch daemonset calico-node --type json -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/timeoutSeconds", "value": 30},
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/periodSeconds", "value": 30},
  {"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/failureThreshold", "value": 6}
]'
```

Note: For Flux-managed resources, commit these changes to git or Flux will revert them.

_____________________________________________________________________

## Stage 5: API Server Request Throttling

### Why
Reducing the maximum concurrent requests to apiserver limits the blast radius of request storms — the exact pattern that triggered the cascade (100x concurrent LIST operations).

### Changes
```yaml
# In kube-apiserver manifest on each master
# /etc/kubernetes/manifests/kube-apiserver.yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --max-requests-inflight=200        # default 400
    - --max-mutating-requests-inflight=100  # default 200
```

### Verify priority & fairness
API Priority and Fairness is on by default in recent K8s versions. Verify the flowschemas are active:
```bash
kubectl get flowschema
kubectl get prioritylevelconfiguration
```

_____________________________________________________________________

## Stage 6: Monitoring Footprint Reduction (Dev Only)

### Why
On constrained dev hardware, aggressive monitoring settings create unnecessary IO load that reduces the headroom available before cascade triggers.

### Changes
- Prometheus scrape interval: 30s instead of 15s (halves scrape IO)
- Flux reconciliation interval: longer for dev (e.g., 10m instead of 1m)
- Promtail scrape interval: increase
- Consider disabling loki-canary (synthetic log generator)
- Reduce Loki retention to 24-48 hours
- Single replica on non-critical monitoring components

_____________________________________________________________________

## Stage 7: Long-term Architecture

### Separate NVMe for etcd (highest impact)
Adding a second NVMe dedicated to etcd data directories prevents etcd fsyncs from competing with VM IO. This is the "proper" fix for the shared-disk contention.

### Consider k3s for dev lab
Full kubeadm K8s has production-grade overhead. k3s uses SQLite instead of etcd, has a single binary, and generates much lower baseline IO. Still teaches K8s concepts but is appropriate for laptop-based dev labs.

### Hardware upgrade path
Current: ASUS laptop, AMD Ryzen 7 7730U, 22GB RAM, single 476.9GB consumer NVMe.
For comfortable K8s dev lab: 32+ GB RAM, separate NVMe for VM disks.

_____________________________________________________________________

## Prioritized Mitigations Summary

Ranked by impact based on the proven root cause:

| Priority | Mitigation | Impact | Effort |
|----------|-----------|--------|--------|
| 1 | Per-VM IO throttling | PRIMARY FIX — prevents single VM from monopolizing NVMe | Low (Proxmox built-in) |
| 2 | Probe timeout tuning | Reduces cascade amplification | Low (manifest edits) |
| 3 | API server request limits | Limits blast radius of request storms | Low (manifest edits) |
| 4 | PodDisruptionBudgets | Prevents all replicas restarting at once | Medium |
| 5 | Monitoring footprint reduction | Increases headroom before cascade | Medium |
| 6 | etcd compaction/defrag | Reduces etcd IO (DB is 46MB, already small) | Low |
| 7 | Separate NVMe for etcd | Eliminates IO contention at architecture level | High (hardware) |

### Trade-offs
**Too-low throttle values**: Cluster baseline operations become slow, probes fail under normal load, etcd slow-apply warnings in steady state.

**Too-high throttle values**: Doesn't prevent cascade — one VM can still saturate enough of the NVMe to starve others.

**Probe timeouts too generous**: Real failures take longer to detect. Acceptable trade-off on dev — cascade prevention matters more than fast failure detection.

**Rollback**: All IO throttle changes are instantly reversible by removing the parameters from the disk config. No VM restart required.
