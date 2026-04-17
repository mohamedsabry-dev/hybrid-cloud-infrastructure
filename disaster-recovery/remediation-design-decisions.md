# Remediation System Design Decisions & Lessons Learned

**Date:** 2026-04-17
**Session:** Full redesign of node self-healing system

---

## Table of Contents
1. [Original System Overview](#original-system-overview)
2. [Issues Discovered](#issues-discovered)
3. [Design Decisions](#design-decisions)
4. [Wrong Approaches & Why They Failed](#wrong-approaches--why-they-failed)
5. [Correct Approaches & Final Solutions](#correct-approaches--final-solutions)
6. [Production vs Homelab Comparison](#production-vs-homelab-comparison)
7. [Testing & Errors Encountered](#testing--errors-encountered)
8. [Final Architecture](#final-architecture)

---

## Original System Overview

### Purpose
Self-healing system for on-prem Kubernetes workers running on Proxmox VMs. When a worker node becomes unhealthy, automatically remediate using escalating actions.

### Original Flow
```
Check every 5 min → Node unhealthy?
  → Attempt 1: Soft reboot
  → Attempt 2: Hard reset
  → Attempt 3: Clone to dump VM → Restore from backup
```

### Original Components
- **ConfigMap**: Python script with remediation logic
- **Deployment**: Runs on master node with high priority
- **ServiceAccount + RBAC**: Access to K8s node/pod status
- **Vault Integration**: Proxmox API credentials

### Original Configuration
```python
CHECK_INTERVAL = 300        # 5 minutes between checks
REMEDIATION_WAIT = 240      # 4 minutes wait after remediation
POD_FAILURE_THRESHOLD = 0.7  # 70% pods failing triggers remediation

NODE_MAP = {
    "k8s-worker1.lab.local": 1020,
    "k8s-worker2.lab.local": 1021,
    "k8s-worker3.lab.local": 1022,
}

DUMP_MAP = {
    "k8s-worker1.lab.local": 5020,
    "k8s-worker2.lab.local": 5021,
    "k8s-worker3.lab.local": 5022,
}
```

---

## Issues Discovered

### Issue 1: Pod Checking Was Unnecessary

**Original Logic:**
- Check if node is Ready
- Check if 70% of pods on node are failing
- If either fails → remediate

**Problem:**
Kubernetes already handles pod-level issues:
- Container crash → kubelet restarts
- OOM kill → kubelet restarts
- Liveness fail → kubelet restarts
- Readiness fail → removed from endpoints
- Pod dies → ReplicaSet schedules on another node

**Risk:**
- Rolling deployment might temporarily show many pods as "not ready"
- Could trigger false positive remediation during normal operations
- ImagePullBackOff during deploy = false positive

**Decision:** Remove all pod-checking logic. Focus only on node Ready status.

---

### Issue 2: Timing Issues - Double Wait

**Original Code:**
```python
def remediate(...):
    reboot_vm(...)
    time.sleep(REMEDIATION_WAIT)  # 4 min wait

# Main loop
for node in nodes:
    if unhealthy:
        remediate(node)  # Blocks 4 min
time.sleep(CHECK_INTERVAL)  # Another 5 min
```

**Problem:**
- After remediation: 4 min + 5 min = 9 minutes before next check
- Too slow to respond if node didn't recover

**Wrong Fix Attempt:**
Added "quick recheck" of 60s after remediation. Still complex.

**Final Decision:**
Remove per-action wait entirely. Just use 5 min check interval.
```python
def remediate(...):
    reboot_vm(...)
    # No wait here

# Main loop
for node in nodes:
    remediate(node)
time.sleep(CHECK_INTERVAL)  # Only wait here
```

---

### Issue 3: Sequential Node Checking

**Original Problem:**
```python
for node in nodes:
    if unhealthy:
        remediate(node)  # Blocks while remediating
        # Other nodes not checked during this time!
```

If worker1 is being remediated (with 4 min wait), worker2 and worker3 are not checked.

**Solution:**
Check all nodes first, then remediate all unhealthy:
```python
# Phase 1: Check ALL nodes
unhealthy_nodes = []
for node in nodes:
    if not healthy:
        unhealthy_nodes.append(node)

# Phase 2: Remediate all
for node in unhealthy_nodes:
    remediate(node)
```

---

### Issue 4: Clone Takes Too Long

**Discovery During Testing:**
- Started clone operation
- Expected: ~1 minute
- Actual: 4 minutes at 30% progress = ~13 minutes total

**Problem Cascade:**
1. Clone starts (locks source VM)
2. After 60s, code continues (clone not done)
3. Tries to delete source VM → fails (locked)
4. Restore fails
5. Next check (5 min) → node still unhealthy
6. Counter increments to 4, 5, 6, 7...
7. "Max attempts exhausted" - but restore never completed

**Log Evidence:**
```
[Attempt 7] Remediating k8s-worker3.lab.local (VM 1022)
  -> Alert sent: all-attempts - exhausted - manual intervention required
```

---

### Issue 5: VM Lock Detection Failed

**Attempted Solution:**
Check if VM is locked before operations:
```python
def is_vm_locked(proxmox, vmid):
    status = proxmox.nodes(NODE).qemu(vmid).status.current.get()
    return "lock" in status
```

**Test Results:**
1. API doesn't return "lock" field in status dict
2. Lock file `/var/lock/qemu-server/lock-1022.conf` exists but is stale
3. Lock file not reliably deleted after operation completes

**Evidence:**
```bash
# VM not locked, but lock file exists:
qm status 1022
# status: stopped

ls -la /var/lock/qemu-server/lock-1022.conf
# -rw-r--r-- 1 root root 0 Apr 17 10:39 /var/lock/qemu-server/lock-1022.conf
```

**Manual Test - Restore During Clone:**
```
Error: unable to restore VM 1022 - can't lock file
'/var/lock/qemu-server/lock-1022.conf' - got timeout (500)
```

**Conclusion:** Lock detection is unreliable. Remove clone step entirely.

---

### Issue 6: Reset on Stopped VM Crashes

**Original reset_vm:**
```python
def reset_vm(proxmox, vmid):
    proxmox.nodes(NODE).qemu(vmid).status.reset.post()
```

**Error:**
```
proxmoxer.core.ResourceException: 500 Internal Server Error: VM 1022 not running
```

**Problem:** `reset` (hard reset) only works on running VMs. If VM is stopped, it crashes.

**Solution:** Check status first, same as reboot_vm:
```python
def reset_vm(proxmox, vmid):
    vm_status = get_vm_status(proxmox, vmid)
    if vm_status == "stopped":
        start_vm(proxmox, vmid)  # Start instead
    elif vm_status == "running":
        proxmox.nodes(NODE).qemu(vmid).status.reset.post()
```

---

### Issue 7: ConfigMap Changes Don't Restart Pod

**Problem:**
Changed ConfigMap, pushed to Git, Flux applied it, but pod kept running old code.

**Why:** Kubernetes doesn't restart pods when ConfigMap changes. Pod must be manually restarted or deployment must change.

**Solution:** Add version annotation to deployment:
```yaml
annotations:
  config-version: "5"  # Bump when ConfigMap changes
```

---

## Design Decisions

### Decision 1: Remove Pod Checking

**Before:**
```python
def is_node_healthy(v1, node_name):
    node_ready = is_node_ready(v1, node_name)
    pods_healthy = are_pods_healthy(v1, node_name)
    return node_ready and pods_healthy
```

**After:**
```python
def is_node_healthy(v1, node_name):
    return is_node_ready(v1, node_name)
```

**Rationale:**
- K8s handles pod-level issues automatically
- Script should only handle what K8s CANNOT fix: VM-level issues
- Removes false positive risk from rolling deployments

---

### Decision 2: Single Replica is Correct

**Question:** Should remediation run 2+ replicas for HA?

**Analysis:**
- 1 replica on master: survives worker failures
- 2 replicas without leader election: both try to reboot same VM = conflict
- Adding leader election: complex, not worth it for homelab

**Decision:** Keep 1 replica with high priority class.

---

### Decision 3: Remove Clone Step

**Original Intent:**
Clone broken VM to `dump-5022` before restoring, to preserve forensic state.

**Problems:**
- Clone takes 13+ minutes (too slow)
- Locks source VM during clone
- Lock detection unreliable
- Causes cascading failures in remediation

**Decision:** Remove clone entirely. Restore directly over existing VM.

**Trade-off:** Lose forensic copy of broken VM. Accept this for simplicity and reliability.

---

### Decision 4: Use Alertmanager for Notifications

**Options Considered:**

| Option | Pros | Cons |
|--------|------|------|
| Direct SMTP | Simple | Duplicate email config |
| Alertmanager API | Reuses existing setup | Depends on Alertmanager |
| Expose /metrics | Native Prometheus | Requires code changes |

**Decision:** Use Alertmanager API (already configured with email).

**Implementation:**
```python
def send_alert(node_name, action, status, severity="warning"):
    alert = [{
        "labels": {
            "alertname": "RemediationAction",
            "node": node_name,
            "action": action,
            "severity": severity
        },
        "annotations": {
            "summary": f"Remediation {action} on {node_name}: {status}"
        }
    }]
    requests.post(ALERTMANAGER_URL, json=alert, timeout=5)
```

---

### Decision 5: Move Alertmanager to Master

**Problem:**
If all workers fail, Alertmanager on worker can't send alerts.

**Solution:**
```yaml
nodeSelector:
  node-role.kubernetes.io/control-plane: ""
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
```

**New Issue:** NFS CSI driver doesn't run on masters → can't mount PVC.

**Solution:** Make Alertmanager stateless with emptyDir:
```yaml
volumes:
  - name: alertmanager-data
    emptyDir: {}
```

**Trade-off:** Silences lost on restart. Acceptable for homelab.

---

## Wrong Approaches & Why They Failed

### Wrong: Quick Recheck After Remediation

**Idea:** After remediation, wait 60s then recheck (instead of full 5 min).

**Code:**
```python
if remediation_performed:
    time.sleep(60)  # Quick recheck
else:
    time.sleep(CHECK_INTERVAL)
```

**Why Wrong:**
- Added complexity
- Still had timing issues with clone
- Better to just use consistent interval

**Correct:** Remove quick recheck. Always use 5 min interval.

---

### Wrong: Check Lock via API

**Idea:** Check `"lock" in status` before operations.

**Code:**
```python
def is_vm_locked(proxmox, vmid):
    status = proxmox.nodes(NODE).qemu(vmid).status.current.get()
    return "lock" in status
```

**Why Wrong:**
- Proxmox API doesn't reliably return lock field
- Lock file on disk can be stale
- Not a reliable indicator

**Correct:** Remove clone step. No need to check locks if we don't clone.

---

### Wrong: Fixed Sleep for Clone Completion

**Idea:** Wait 60s after starting clone.

**Code:**
```python
proxmox.nodes(NODE).qemu(vmid).clone.post(...)
time.sleep(60)  # Wait for clone
```

**Why Wrong:**
- Clone actually takes 13+ minutes
- Fixed sleep doesn't match actual operation time
- Would need to poll task API (complex)

**Correct:** Remove clone step entirely.

---

## Production vs Homelab Comparison

### How Production Handles Node Self-Healing

**Cloud (AWS/GCP/Azure):**
```
Node unhealthy → Terminate instance → Auto Scaling creates new one
```
- Nodes are **cattle** (disposable, no identity)
- No backup/restore - destroy and recreate
- Bootstrap via cloud-init/user-data
- Takes 3-5 minutes

**On-prem with Cluster API:**
```
MachineHealthCheck → Delete Machine CR → Controller creates new VM from template
```
- Uses VM templates (not backups)
- Same pattern as cloud
- Works with vSphere, Nutanix, Proxmox (community)

### Why Homelab is Different

**Homelab Identity Requirements:**
- IPA enrolled (Kerberos principal)
- DNS managed by IPA
- SSH host keys (Ansible trust)
- Terraform tracks VMID, MAC, IP
- Cloud-init already ran

**New VM from Template Would Break:**
- TF state (new VMID)
- IPA enrollment
- SSH key trust
- Ansible connectivity

**Why Restore is Correct for Homelab:**
- Same VMID → TF happy
- Same MAC → Same IP
- Same hostname → IPA still valid
- Same SSH keys → Ansible works

---

## Testing & Errors Encountered

### Test 1: Basic Remediation Flow

**Action:** Shut down worker3 VM manually.

**Expected:** Remediation detects and reboots.

**Actual:**
```
k8s-worker3.lab.local: UNHEALTHY! (Node NotReady)
[Attempt 1] Remediating k8s-worker3.lab.local (VM 1022)
  -> VM 1022 status: stopped
  -> VM 1022 is stopped, starting instead of rebooting
  -> Starting VM 1022
  -> Alert sent: reboot - initiated
```

**Result:** ✅ Worked correctly.

---

### Test 2: Reset on Stopped VM

**Action:** Shut down VM, wait for attempt 2.

**Error:**
```
proxmoxer.core.ResourceException: 500 Internal Server Error: VM 1022 not running
```

**Fix:** Add status check to reset_vm (same as reboot_vm).

---

### Test 3: Clone During Restore

**Action:** Trigger restore with clone step.

**Observation:**
- Clone started, showed 30% after 4 minutes
- Estimated total: 13+ minutes
- Source VM locked during clone

**Error when trying to restore during clone:**
```
unable to restore VM 1022 - can't lock file
'/var/lock/qemu-server/lock-1022.conf' - got timeout (500)
```

**Fix:** Remove clone step entirely.

---

### Test 4: Alertmanager on Master

**Action:** Moved Alertmanager to master node.

**Error:**
```
MountVolume.MountDevice failed for volume "pvc-...":
driver name nfs.csi.k8s.io not found in the list of registered CSI drivers
```

**Cause:** NFS CSI driver DaemonSet doesn't tolerate master taints.

**Fix:** Make Alertmanager stateless (emptyDir instead of PVC).

---

### Test 5: Email Notifications

**Action:** Stop node_exporter on ansible.lab.local.

**Result:** ✅ Received email after TargetDown alert fired.

```
[FIRING:1] (TargetDown external-nodes monitoring/kube-prometheus-stack-prometheus warning)
description = 14.29% of the external-nodes/ targets in namespace are down.
```

**Issue:** Alert doesn't say WHICH target is down.

**Fix:** Create custom PrometheusRule with per-instance alerts:
```yaml
- alert: ExternalNodeDown
  expr: up{job="external-nodes"} == 0
  for: 2m
  annotations:
    summary: "{{ $labels.instance }} is down"
```

---

## Final Architecture

### Simplified Flow
```
Every 5 minutes:
  1. Check ALL nodes for Ready status
  2. Collect unhealthy nodes
  3. For each unhealthy node:
     - Attempt 1: Soft reboot (or start if stopped)
     - Attempt 2: Hard reset (or start if stopped)
     - Attempt 3: Restore from backup (direct, no clone)
     - Attempt 4+: Alert "exhausted, manual intervention"
  4. Send alert for each action
  5. If node recovers, send recovery alert and reset counter
```

### Final Configuration
```python
CHECK_INTERVAL = 300  # 5 minutes

NODE_MAP = {
    "k8s-worker1.lab.local": 1020,
    "k8s-worker2.lab.local": 1021,
    "k8s-worker3.lab.local": 1022,
}
# No DUMP_MAP - clone removed
# No REMEDIATION_WAIT - use check interval
# No POD_FAILURE_THRESHOLD - node-only checking
```

### Files Modified

| File | Change |
|------|--------|
| `remediation/configmap.yaml` | Simplified script, removed pod/clone logic |
| `remediation/deployment.yaml` | Added config-version annotation |
| `alertmanager/statefulset.yaml` | Moved to master, made stateless |
| `monitoring/custom-alerts.yaml` | Added per-instance alerts |
| `monitoring/helm-release.yaml` | Disabled stack alertmanager |

### What We Kept
- Escalating remediation (reboot → reset → restore)
- Running on master node
- High priority class
- Vault integration for Proxmox credentials
- Alert notifications via Alertmanager

### What We Removed
- Pod failure checking (K8s handles this)
- Clone to dump VM (too slow, caused locks)
- Per-action wait times (use interval only)
- Lock checking (unreliable)
- Quick recheck logic (unnecessary complexity)

---

## Key Learnings

1. **Start simple.** The original script tried to handle too many cases.

2. **Understand what K8s already does.** Don't replicate pod-level handling.

3. **Test with real timing.** Clone taking 13 min wasn't discovered until testing.

4. **Lock detection is unreliable.** Both API and file-based checks failed.

5. **Homelab != Cloud.** Nodes have identity that must be preserved.

6. **Stateless is simpler.** Alertmanager doesn't need persistence for homelab.

7. **Check status before actions.** VMs can be in unexpected states.

8. **ConfigMaps need pod restart.** Use annotation versioning.

---

## Successful Test Results (2026-04-17)

### Full Remediation Flow Tested

**Scenario:** Shut down worker2 and worker3 manually.

**Results:**
```
--- Health check ---
k8s-worker1.lab.local: Healthy
k8s-worker2.lab.local: UNHEALTHY! (Node NotReady)
[Attempt 1] Remediating k8s-worker2.lab.local (VM 1021)
  -> VM 1021 status: stopped
  -> Starting VM 1021
  -> Alert sent: reboot - initiated

[Attempt 2] Remediating k8s-worker2.lab.local (VM 1021)
  -> VM 1021 status: stopped
  -> Starting VM 1021
  -> Alert sent: reset - initiated

[Attempt 3] Remediating k8s-worker3.lab.local (VM 1022)
  -> Stopping VM 1022
  -> Deleting VM 1022
  -> Restoring from nas-dev-data:backup/vzdump-qemu-1022-2026_04_16-21_09_39.vma.zst
  -> Restore initiated, VM 1022 starting
  -> Alert sent: restore - initiated

--- Next health check ---
k8s-worker2.lab.local: Recovered! Resetting counter.
  -> Alert sent: recovery - node is healthy again
k8s-worker3.lab.local: Recovered! Resetting counter.
  -> Alert sent: recovery - node is healthy again
```

**All nodes recovered:**
```
NAME                    CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
k8s-master1.lab.local   449m         22%      1700Mi          80%
k8s-master2.lab.local   179m         8%       1579Mi          74%
k8s-master3.lab.local   164m         8%       1586Mi          75%
k8s-worker1.lab.local   133m         6%       2093Mi          73%
k8s-worker2.lab.local   170m         8%       1882Mi          65%
k8s-worker3.lab.local   142m         7%       1566Mi          54%
```

### Restore Timing

| Phase | Duration |
|-------|----------|
| Proxmox restore API call | Instant (async) |
| Actual restore from backup | ~3.5 minutes |
| VM boot + K8s node Ready | ~1-2 minutes |
| **Total** | ~5 minutes |

**Problem:** Restore API returns immediately, but actual restore takes 3.5 min.
If CHECK_INTERVAL (5 min) passes before restore completes, next check would try to remediate again.

**Solution:** Added 2 minute buffer sleep after triggering restore.
```python
if result == "restored":
    send_alert(node_name, "restore", "initiated", severity="critical")
    print(f"  -> Waiting 120s buffer for restore to complete...")
    time.sleep(120)  # 2 min buffer
```

**New timing after restore:**
- 2 min buffer + 5 min interval = 7 min before next check
- Gives restore enough time to complete

### Workload Distribution After Recovery

**Observation:** Worker3 had lower load after recovery.

**Why:** Kubernetes scheduler places NEW pods but doesn't rebalance existing ones.
During outage, pods were scheduled to worker1/2 and stayed there.

**Solutions:**
1. Manual: `kubectl rollout restart deployment <name>`
2. Automatic: Deploy Descheduler to rebalance

---

## Future Improvements

1. **Add /metrics endpoint** - Expose remediation metrics to Prometheus
2. **Grafana dashboard** - Visualize remediation history
3. **Descheduler** - Auto-rebalance workloads after node recovery
4. **Document runbook** - Manual intervention steps when automation fails
5. **CPU alerts** - Alert on high CPU (qemu-ga bug discovered during testing)
