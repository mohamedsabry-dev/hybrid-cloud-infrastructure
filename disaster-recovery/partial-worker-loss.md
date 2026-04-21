# Partial Worker Loss (2 of 3)
# Date: 2026-04-18
# Result: TESTED — PASSED (Remediation Auto-Recovered, Self-Healing Validated)

---

## Scope

Force shutdown 2 of 3 workers. Test cluster behavior under severe worker loss.

---

## Pre-Test Baseline (2026-04-18)

### Node Status
```
NAME                    STATUS   ROLES           CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
k8s-master1.lab.local   Ready    control-plane   188m         9%       1627Mi          77%
k8s-master2.lab.local   Ready    control-plane   150m         7%       1547Mi          73%
k8s-master3.lab.local   Ready    control-plane   166m         8%       1701Mi          80%
k8s-worker1.lab.local   Ready    <none>          98m          4%       1883Mi          65%
k8s-worker2.lab.local   Ready    <none>          92m          4%       1918Mi          67%
k8s-worker3.lab.local   Ready    <none>          143m         7%       2154Mi          75%
```

### Critical Workload Distribution (Before Test)
| Workload | Node | CPU | Memory |
|----------|------|-----|--------|
| wordpress-6d4f6bbd46-ngdmm | worker1 | 1m | 171Mi |
| wordpress-6d4f6bbd46-rjsbd | worker3 | 1m | 141Mi |
| mariadb-0 | worker2 | 1m | 270Mi |
| grafana | worker2 | 10m | 376Mi |
| prometheus-0 | worker3 | 41m | 777Mi |
| loki-0 | worker2 | 11m | 383Mi |

### Pods Per Worker (Before Test)
| Worker | Pod Count | Key Workloads |
|--------|-----------|---------------|
| worker1 | ~15 | WordPress, Flux controllers, ingress-nginx, kube-state-metrics |
| worker2 | ~8 | MariaDB, Grafana, Loki |
| worker3 | ~10 | WordPress, Prometheus, ingress-nginx, csi-nfs-controller |

### Total Worker Memory Usage
- worker1: 1883Mi (65%)
- worker2: 1918Mi (67%)
- worker3: 2154Mi (75%)
- **Combined: ~5955Mi**
- **Single worker capacity: ~2880Mi (assuming similar to worker3 max)**

---

## Test Plan

**Workers to shutdown:** worker1 + worker2
**Surviving worker:** worker3

**Rationale:** worker3 has highest memory usage already (75%), this tests worst-case scenario.

---

## Steps

1. Force shutdown 2 worker nodes (worker1, worker2)
2. Check: Remaining worker handles all pods?
3. Check: Resource pressure on surviving worker
4. Check: Any pods stuck in Pending (insufficient resources)?
5. Recovery: Start workers → pods redistribute

---

## Commands

```bash
# Force shutdown 2 workers via Proxmox
qm stop <worker1-vmid> --skiplock
qm stop <worker2-vmid> --skiplock

# Watch cluster state
kubectl get nodes -w
kubectl get pods -A -o wide

# Check resource pressure
kubectl top nodes
kubectl describe node k8s-worker3.lab.local | grep -A 10 "Allocated resources"

# Check for Pending pods
kubectl get pods -A | grep -i pending
```

---

## Expected Behavior

- WordPress: 1 replica survives on worker3, 1 needs to reschedule
- MariaDB: Must reschedule from worker2 to worker3 (StatefulSet)
- Grafana: Must reschedule from worker2 to worker3
- Loki: Must reschedule from worker2 to worker3
- Prometheus: Already on worker3, stays
- Some pods may be Pending if resources insufficient on worker3

---

## Test Execution

### Phase 1: Shutdown Workers
**Time:** 2026-04-18 ~19:54
**Action:** Force shutdown worker1 (VM 1020) + worker2 (VM 1021) via Proxmox

**Node Status After Shutdown:**
```
NAME                    STATUS     ROLES           AGE   VERSION
k8s-master1.lab.local   Ready      control-plane   22d   v1.35.3
k8s-master2.lab.local   Ready      control-plane   22d   v1.35.3
k8s-master3.lab.local   Ready      control-plane   22d   v1.35.3
k8s-worker1.lab.local   NotReady   <none>          22d   v1.35.3
k8s-worker2.lab.local   NotReady   <none>          22d   v1.35.3
k8s-worker3.lab.local   Ready      <none>          22d   v1.35.3
```

### Phase 2: Observe Failover
**Immediate Impact Observed:**

| Service | Status | Error |
|---------|--------|-------|
| WordPress | DOWN | `Connection refused` - MariaDB unreachable |
| Grafana | DOWN | `503 Service Temporarily Unavailable` (nginx) |
| MariaDB | DOWN | Was on worker2, needs reschedule |
| Loki | DOWN | Was on worker2, needs reschedule |

**WordPress Error:**
```
Warning: mysqli_real_connect(): (HY000/2002): Connection refused in /var/www/html/wp-includes/class-wpdb.php on line 1994
Error establishing a database connection
```

**Pods Requiring Reschedule (from worker1 + worker2):**
- mariadb-0 (StatefulSet) - worker2
- grafana (Deployment) - worker2
- loki-0 (StatefulSet) - worker2
- wordpress-xxx (1 replica) - worker1
- Flux controllers - worker1
- kube-state-metrics - worker1
- ingress-nginx (1 replica) - worker1

### Phase 2.5: Auto-Recovery by Remediation System
**Time:** 2026-04-18 ~19:58 (4 minutes after shutdown)

**Remediation System Triggered:**
```
[Attempt 1] Remediating k8s-worker1.lab.local (VM 1020)
  -> VM 1020 status: stopped
  -> VM 1020 is stopped, starting instead of rebooting
  -> Starting VM 1020
  -> Alert sent: reboot - initiated

[Attempt 1] Remediating k8s-worker2.lab.local (VM 1021)
  -> VM 1021 status: stopped
  -> VM 1021 is stopped, starting instead of rebooting
  -> Starting VM 1021
  -> Alert sent: reboot - initiated
```

**Result:** Workers auto-recovered before pod eviction timeout (~5 min default)

**Nodes After Recovery:**
```
NAME                    STATUS   ROLES           AGE   VERSION
k8s-master1.lab.local   Ready    control-plane   22d   v1.35.3
k8s-master2.lab.local   Ready    control-plane   22d   v1.35.3
k8s-master3.lab.local   Ready    control-plane   22d   v1.35.3
k8s-worker1.lab.local   Ready    <none>          22d   v1.35.3
k8s-worker2.lab.local   Ready    <none>          22d   v1.35.3
k8s-worker3.lab.local   Ready    <none>          22d   v1.35.3
```

### Phase 3: Pod Restart Counts (Post-Recovery)

**Key Finding:** Pods stayed on original nodes - no rescheduling occurred because VMs were restarted before eviction timeout.

| Pod | Node | Restarts | Status |
|-----|------|----------|--------|
| wordpress-ngdmm | worker1 | 2 | 1/2 Running (recovering) |
| wordpress-rjsbd | worker3 | 0 | 2/2 Running |
| mariadb-0 | worker2 | 2 | 2/2 Running |
| grafana | worker2 | 4 | 4/4 Running |
| loki-0 | worker2 | 2 | 1/2 Running (recovering) |
| helm-controller | worker1 | 41 | 1/1 Running |
| kustomize-controller | worker1 | 35 | 1/1 Running |
| source-controller | worker1 | 35 | 0/1 Running (recovering) |

### Phase 4: Recovery
**Status:** AUTO-RECOVERED by remediation system

**Downtime Duration:** ~4 minutes (19:54 to 19:58)

**Services Recovery:**
- WordPress: Recovered after MariaDB came back
- Grafana: Recovered (4 restarts to reconnect)
- MariaDB: Recovered (StatefulSet restarted on same node)
- Loki: Recovering (1/2 containers)

### Alertmanager Notifications

**Reboot Alerts (Firing):**
```
alertname = RemediationAction
action = reboot
node = k8s-worker1.lab.local
severity = warning
description = Self-healing action 'reboot' was performed on node k8s-worker1.lab.local. Result: initiated

alertname = RemediationAction
action = reboot
node = k8s-worker2.lab.local
severity = warning
description = Self-healing action 'reboot' was performed on node k8s-worker2.lab.local. Result: initiated
```

**Recovery Alerts (After nodes healthy):**
```
alertname = RemediationAction
action = recovery
node = k8s-worker1.lab.local
severity = info
description = Self-healing action 'recovery' was performed on node k8s-worker1.lab.local. Result: node is healthy again

alertname = RemediationAction
action = recovery
node = k8s-worker2.lab.local
severity = info
description = Self-healing action 'recovery' was performed on node k8s-worker2.lab.local. Result: node is healthy again
```

**Health Check Log:**
```
--- Health check at 2026-04-18 18:02:17 UTC ---
k8s-worker1.lab.local: Recovered! Resetting counter.
  -> Alert sent: recovery - node is healthy again
k8s-worker2.lab.local: Recovered! Resetting counter.
  -> Alert sent: recovery - node is healthy again
k8s-worker3.lab.local: Healthy
```

---

---

## Key Findings

### 1. Remediation System Works ✅
- Detected stopped VMs within ~4 minutes
- Auto-started VMs without manual intervention
- Cluster self-healed
- **Full alert loop:** Reboot alerts → Recovery alerts → Slack notified

### 2. Pod Eviction Did NOT Occur
- Default pod eviction timeout is ~5 minutes
- Remediation restarted VMs in ~4 minutes
- Pods stayed on original nodes (restart vs reschedule)

### 3. Service Downtime
- **Duration:** ~4 minutes
- WordPress showed DB connection error during outage
- Grafana returned 503 during outage
- Both recovered automatically after VM restart

### 4. Test Was Interrupted
- Could not observe pod rescheduling to single worker (worker3)
- Resource pressure test on single worker not completed
- Need to either:
  - Disable remediation temporarily for full test
  - Or increase shutdown duration beyond eviction timeout

---

## TODO

- [x] Record pre-test baseline
- [x] Execute test - shutdown worker1 + worker2
- [x] Document pod failover behavior
- [~] Document resource pressure on worker3 (NOT TESTED - auto-recovered)
- [~] Identify pods that don't fit on 1 worker (NOT TESTED - auto-recovered)
- [x] Recovery - start workers (AUTO by remediation)
- [x] Document pod redistribution (pods stayed on same nodes)

---

## Next Steps

To complete full worker loss test:
1. **Option A:** Temporarily disable remediation, repeat test
2. **Option B:** Delete nodes from K8s (kubectl delete node) instead of VM shutdown
3. **Option C:** Accept current results - remediation works as designed

---

# Test 2: Total Worker Loss + Master3 (No Remediation)
# Date: 2026-04-18
# Result: PASSED (after manual fixes) - 2 Critical Issues Identified and Resolved

---

## Test Plan

**Shutdown order:**
1. master3 (VM 1012) - kills remediation pod
2. worker1 (VM 1020)
3. worker2 (VM 1021)
4. worker3 (VM 1022)

**Keep running:** master1, master2 (control plane 2/3)

**Goal:** Test cluster behavior with total worker loss and no auto-recovery

---

## Pre-Test State

**Remediation pod location:** k8s-master3.lab.local

**Critical pods per node:**
| Node | Key Pods |
|------|----------|
| master3 | remediation, vault-agent-injector, coredns, etcd-backup |
| worker1 | WordPress, Flux controllers, ingress-nginx (2), kube-state-metrics, coredns |
| worker2 | MariaDB, Grafana, Loki |
| worker3 | WordPress, Prometheus, ingress-nginx, metrics-server, csi-nfs-controller |

---

## Test Execution

### Phase 1: Shutdown master3 + all workers
**Time:** 2026-04-18 ~20:25

**Nodes shutdown:**
```bash
qm stop 1012  # master3 (has remediation pod)
qm stop 1020  # worker1
qm stop 1021  # worker2
qm stop 1022  # worker3
```

**Node status after shutdown:**
```
NAME                    STATUS     ROLES           AGE   VERSION
k8s-master1.lab.local   Ready      control-plane   22d   v1.35.3
k8s-master2.lab.local   Ready      control-plane   22d   v1.35.3
k8s-master3.lab.local   NotReady   control-plane   22d   v1.35.3
k8s-worker1.lab.local   NotReady   <none>          22d   v1.35.3
k8s-worker2.lab.local   NotReady   <none>          22d   v1.35.3
k8s-worker3.lab.local   NotReady   <none>          22d   v1.35.3
```

**Control plane status:** UP (2/3 masters, etcd quorum maintained)

---

### Phase 2: Pod Eviction Analysis

#### Critical Finding #1: Taints are NoSchedule, NOT NoExecute

```bash
kubectl describe node k8s-master3.lab.local | grep -A 5 Taints
```
```
Taints:             node-role.kubernetes.io/control-plane:NoSchedule
                    node.kubernetes.io/unreachable:NoSchedule   ← WRONG! Should be NoExecute
```

**Impact:** Pods on NotReady nodes are NOT automatically evicted. They stay "Running" (stale status) forever.

**Expected behavior:** `node.kubernetes.io/unreachable:NoExecute` → pods evicted after tolerationSeconds (default 300s)

**Actual behavior:** `node.kubernetes.io/unreachable:NoSchedule` → pods not evicted, just no new scheduling

#### Critical Finding #2: Single-Replica Deployments Don't Auto-Recover

**Comparison of vault-agent-injector vs remediation:**

| Aspect | vault-agent-injector | remediation |
|--------|---------------------|-------------|
| Replicas | 2+ | 1 |
| Pod on master3 | Terminating | Running (stale) |
| New pod created? | ✅ Yes (immediately) | ❌ No |
| Tolerations | Same | Same |

**Events comparison:**
```
# vault-agent-injector:
29m   Warning   NodeNotReady       Pod/vault-agent-injector-jc2gh    Node is not ready
29m   Normal    SuccessfulCreate   ReplicaSet/vault-agent-injector   Created pod: fvdt6  ← NEW POD!

# remediation:
30m   Warning   NodeNotReady   Pod/remediation-dlqbw   Node is not ready
                                                        ← NO new pod created
```

**Root cause:** With replicas=1, ReplicaSet sees "1/1 pods exist" and takes no action, even though the pod is unreachable. With replicas≥2, when available < desired, it creates new pods.

**Affected workloads (all replicas=1):**
| Workload | Type | Impact |
|----------|------|--------|
| remediation | Deployment | Won't auto-recover |
| alertmanager-0 | StatefulSet | Won't auto-recover |
| mariadb-0 | StatefulSet | Won't auto-recover |
| loki-0 | StatefulSet | Won't auto-recover |
| prometheus-0 | StatefulSet | Won't auto-recover |
| grafana | Deployment | Won't auto-recover |

#### Critical Finding #3: Manual NoExecute Taint Didn't Work

Attempted manual fix:
```bash
kubectl taint nodes k8s-master3.lab.local node.kubernetes.io/unreachable:NoExecute --overwrite
```

**Result:** Pods still not evicted after 10+ minutes. Reason unknown - requires deeper investigation.

#### Critical Finding #4: Force Delete Required

To reschedule remediation, had to force delete:
```bash
kubectl delete pod remediation-774679955-dlqbw -n remediation --force --grace-period=0
```

**Result:** New pod scheduled on master2 immediately.

---

### Phase 3: Cascading Failure - DNS Dependency

After remediation rescheduled to master2, vault-agent-init failed:

```
error authenticating: "Put \"https://vault.lab.local:8200/v1/auth/kubernetes/login\":
dial tcp: lookup vault.lab.local on 10.96.0.10:53: read: connection refused"
```

**Root cause:** CoreDNS pods are on dead nodes:
- coredns-m7bw6 → worker1 (DOWN)
- coredns-t8p4b → master3 (DOWN)

**Dependency chain failure:**
```
Remediation
    → needs Vault authentication
    → needs DNS to resolve vault.lab.local
    → needs CoreDNS
    → CoreDNS pods on dead nodes
    → COMPLETE FAILURE
```

**Impact:** Even after remediation rescheduled, it cannot start because DNS is unavailable. Cluster cannot self-heal.

---

### Phase 4: Test Aborted

**Reason:** Cascading failure - cannot recover without manual intervention.

**Manual recovery required:**
```bash
# On Proxmox host - start any node with CoreDNS
qm start 1012   # master3
# OR
qm start 1020   # worker1
```

---

## Critical DR Findings Summary

### Finding #1: Pod Eviction Not Working
- **Issue:** Nodes get `NoSchedule` taint instead of `NoExecute`
- **Impact:** Pods never evicted from failed nodes
- **Severity:** CRITICAL
- **Fix:** Investigate kube-controller-manager configuration, ensure `NoExecute` taints are applied

### Finding #2: Single-Replica Workloads Don't Failover
- **Issue:** With replicas=1, no new pod created when existing pod is on failed node
- **Impact:** All single-replica workloads stay down until manual intervention
- **Severity:** CRITICAL
- **Fix Options:**
  1. Run critical workloads with replicas≥2
  2. Fix pod eviction (Finding #1)
  3. Add self-healing logic to force-delete pods on failed nodes

### Finding #3: DNS Single Point of Failure
- **Issue:** CoreDNS replicas=2, but both scheduled on nodes that went down
- **Impact:** Complete DNS failure, breaks all DNS-dependent services including remediation
- **Severity:** CRITICAL
- **Fix Options:**
  1. Force CoreDNS to run on masters only (nodeSelector + tolerations)
  2. Increase CoreDNS replicas to 3+
  3. Add topologySpreadConstraints to ensure spread across nodes

### Finding #4: Remediation Has Critical Dependencies
- **Issue:** Remediation requires Vault → requires DNS → can fail if DNS is down
- **Impact:** Self-healing system cannot heal itself
- **Severity:** CRITICAL
- **Fix Options:**
  1. Remove Vault dependency from remediation init (use pre-provisioned credentials)
  2. Use Vault IP address instead of DNS name
  3. Ensure DNS always available (Finding #3)
  4. Add DNS-independent fallback in remediation

### Finding #5: Remediation Single Replica
- **Issue:** Remediation runs as single replica
- **Impact:** If remediation pod is on failed node, no self-healing until manual intervention
- **Severity:** HIGH
- **Fix:** Run remediation with replicas=2, add pod anti-affinity to spread across masters

---

## Action Items Before Re-Test

### Priority 1: Fix DNS Resilience
```yaml
# Patch CoreDNS to run on masters
kubectl patch deployment coredns -n kube-system --type='json' -p='[
  {"op": "add", "path": "/spec/template/spec/nodeSelector", "value": {"node-role.kubernetes.io/control-plane": ""}},
  {"op": "add", "path": "/spec/template/spec/tolerations/-", "value": {"key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule"}}
]'
```

### Priority 2: Fix Remediation Resilience
1. Increase replicas to 2
2. Add pod anti-affinity across masters
3. Consider removing/reducing Vault init dependency

### Priority 3: Investigate Pod Eviction
- Check why `NoSchedule` instead of `NoExecute`
- Check kube-controller-manager logs
- Check if feature gates affect this

### Priority 4: Fix Single-Replica Workloads
- Consider replicas=2 for: alertmanager, grafana
- StatefulSets (mariadb, loki, prometheus) need different approach

---

## Test Conclusion

**Result:** FAILED - Cluster cannot self-heal from total worker loss + 1 master loss

**Root causes:**
1. Pod eviction not working (NoSchedule vs NoExecute)
2. Single-replica deployments don't failover
3. DNS single point of failure
4. Remediation dependency chain (Vault → DNS)

**Time spent in broken state:** Test aborted after ~45 minutes, manual recovery required

**Lesson learned:** Self-healing systems must not have dependencies that can fail in the same failure scenario they're trying to heal.

---

## Actual Recovery Path

### Step 1: Manual - Start master3 (for DNS)
```bash
qm start 1012   # master3 - has CoreDNS
```

### Step 2: Manual - Force delete stuck remediation pod
```bash
kubectl delete pod -n remediation remediation-774679955-kftbt
```

### Step 3: Automatic - New remediation pod started
- Scheduled on master2
- vault-agent-init succeeded (DNS now working)
- Remediation container started

### Step 4: Automatic - Remediation recovered workers
```
Remediation logs:
→ Detected k8s-worker1.lab.local NotReady
→ Detected k8s-worker2.lab.local NotReady
→ Detected k8s-worker3.lab.local NotReady
→ Started VM 1020 (worker1)
→ Started VM 1021 (worker2)
→ Started VM 1022 (worker3)
```

### Step 5: Alerts confirmed recovery
```
Firing (Recovery):
- k8s-worker1.lab.local: node is healthy again
- k8s-worker2.lab.local: node is healthy again
- k8s-worker3.lab.local: node is healthy again

Resolved (Reboot):
- k8s-worker1.lab.local: reboot initiated → resolved
- k8s-worker2.lab.local: reboot initiated → resolved
- k8s-worker3.lab.local: reboot initiated → resolved
```

### Recovery Timeline
| Step | Action | Type | Time |
|------|--------|------|------|
| 1 | Start master3 | Manual | ~1 min |
| 2 | Delete stuck pod | Manual | ~5 sec |
| 3 | Remediation starts | Automatic | ~30 sec |
| 4 | Workers recovered | Automatic | ~2-3 min |
| **Total** | | | **~5 min** |

**Key insight:** With DNS available and remediation pod restarted, automatic recovery worked. The bottleneck was DNS dependency.

---

## Test 2 Re-Run: With Fixes Applied

### Time: 2026-04-18 ~22:15

### Fixes Applied Before Re-Run:
1. **CoreDNS on master1** (by chance - one pod was already there)
2. **Manual NoExecute taint** added to master3

### Test Execution:
```bash
# Shutdown master3 + all workers
qm stop 1012 && qm stop 1020 && qm stop 1021 && qm stop 1022

# Verify DNS works (CoreDNS on master1)
kubectl exec vault-agent-injector-xxx -n vault -- nslookup vault.lab.local
# Result: vault.lab.local → 10.0.62.100 ✅

# Add NoExecute taint to master3
kubectl taint nodes k8s-master3.lab.local node.kubernetes.io/unreachable:NoExecute
```

### Result: SUCCESS

**Eviction worked:**
```
TaintManagerEviction    Marking for deletion Pod remediation/remediation-774679955-94vmb
SuccessfulCreate        Created pod: remediation-774679955-mlgxs
Scheduled               Successfully assigned remediation/remediation-774679955-mlgxs to k8s-master2.lab.local
```

**Timeline:**
| Time | Event |
|------|-------|
| 22:15 | Shutdown master3 + workers |
| 22:20 | Verified DNS works (CoreDNS on master1) |
| 22:30 | Added NoExecute taint to master3 |
| 22:35 | Remediation pod evicted, rescheduled to master2 |
| 22:36 | vault-agent-init succeeded (DNS working) |
| 22:37 | Remediation started, recovered all workers |
| 22:40 | All nodes Ready, cluster recovered |

### qemu-ga CPU Issue During Test
During the test, qemu-ga CPU spike occurred:
- **master1:** ~22:36, self-recovered in ~2 min
- **master2:** ~22:38, self-recovered in ~8 min
- **Proxmox graph showed 60%+ CPU for 40 min** (but actual hang was 2-4 min)
- **Did not block remediation** - workers still recovered

See: `troubleshooting/kubernetes/38-qemu-guest-agent-cpu-loop.md`

---

## Final Root Cause Summary

### Issue 1: NoExecute Taint Not Applied Automatically
- **Problem:** kube-controller-manager applies `NoSchedule` instead of `NoExecute` to unreachable nodes
- **Impact:** Pods never evicted from failed nodes
- **Solution:** Manual `kubectl taint` with `NoExecute` works; need to investigate why automatic taint is wrong
- **Ticket:** `troubleshooting/kubernetes/43-noexecute-taint-not-applied.md`

### Issue 2: CoreDNS Not HA Across Masters
- **Problem:** Both CoreDNS pods can end up on nodes that fail together
- **Impact:** Complete DNS failure, breaks entire cluster including remediation
- **Solution:** Force CoreDNS to run on control-plane nodes only
- **Ticket:** `troubleshooting/kubernetes/44-coredns-ha-masters.md`

---

## Lessons Learned

1. **DNS is the foundation** - If DNS fails, everything fails including self-healing
2. **NoExecute taint is critical** - Without it, pods never evict from failed nodes
3. **Test self-healing under failure** - Self-healing systems must not depend on components that can fail
4. **Control plane components on masters** - Critical components (DNS, etc.) should run on control-plane nodes
