# Issue: NoExecute Taint Not Applied Automatically to Unreachable Nodes

**Status:** RESOLVED
**Date Discovered:** 2026-04-18
**Severity:** CRITICAL
**Discovered During:** DR Test 2 - Total Worker Loss

---

## Summary

When nodes become unreachable (NotReady), Kubernetes applies `NoSchedule` taint instead of `NoExecute`. This prevents automatic pod eviction from failed nodes.

---

## Symptoms

```bash
kubectl describe node k8s-master3.lab.local | grep -A 5 Taints
```

**Expected:**
```
Taints:  node.kubernetes.io/unreachable:NoExecute
```

**Actual:**
```
Taints:  node.kubernetes.io/unreachable:NoSchedule   ← WRONG!
```

---

## Impact

- Pods on unreachable nodes stay "Running" (stale status)
- ReplicaSets don't create replacement pods
- Self-healing systems fail
- Manual intervention required to recover

---

## Evidence

### DR Test 2 - Inconsistent Behavior

| Node | NoExecute | NoSchedule |
|------|-----------|------------|
| master3 | ❌ NO | ✅ Yes |
| worker1 | ❌ NO | ✅ Yes |
| worker2 | ✅ YES | ✅ Yes |
| worker3 | ❌ NO | ✅ Yes |

Only worker2 got `NoExecute` taint.

### DR Test 3 - Same Pattern (after CoreDNS fix)

| Node | NoExecute | NoSchedule |
|------|-----------|------------|
| master2 | ❌ NO | ✅ Yes |
| worker1 | ✅ YES | ✅ Yes |
| worker2 | ❌ NO | ✅ Yes |
| worker3 | ❌ NO | ✅ Yes |

Only worker1 got `NoExecute` taint. **Pattern confirms PartialDisruption rate-limiting.**

### DR Test 4 - After Fix (--unhealthy-zone-threshold=0.8)

| Node | NoExecute | NoSchedule | Status |
|------|-----------|------------|--------|
| master1 | - | Yes | UP |
| master2 | ✅ YES | Yes | DOWN |
| master3 | - | Yes | UP |
| worker1 | ✅ YES | Yes | DOWN |
| worker2 | ✅ YES | Yes | DOWN |
| worker3 | ✅ YES | Yes | DOWN |

**ALL down nodes got NoExecute!** Fix confirmed working.

### DR Test 4 - Full Recovery Evidence

**1. Taints applied correctly:**
```
NAME                    TAINTS
k8s-master2.lab.local   NoSchedule,NoSchedule,NoExecute
k8s-worker1.lab.local   NoSchedule,NoExecute
k8s-worker2.lab.local   NoSchedule,NoExecute
k8s-worker3.lab.local   NoSchedule,NoExecute
```

**2. Remediation evicted and rescheduled:**
```
remediation     Normal    TaintManagerEviction    pod/remediation-774679955-mlgxs    Marking for deletion Pod remediation/remediation-774679955-mlgxs
remediation     Normal    SuccessfulCreate        replicaset/remediation-774679955   Created pod: remediation-774679955-2bjsh
remediation     Normal    Scheduled               pod/remediation-774679955-2bjsh    Successfully assigned remediation/remediation-774679955-2bjsh to k8s-master3.lab.local
```

**3. Remediation detected unhealthy workers:**
```
k8s-worker1.lab.local: UNHEALTHY! (Node NotReady)
k8s-worker2.lab.local: UNHEALTHY! (Node NotReady)
k8s-worker3.lab.local: UNHEALTHY! (Node NotReady)

--- Remediating 3 unhealthy node(s) ---
[Attempt 1] Remediating k8s-worker1.lab.local (VM 1020)
  -> VM 1020 is stopped, starting instead of rebooting
  -> Starting VM 1020
[Attempt 1] Remediating k8s-worker2.lab.local (VM 1021)
  -> VM 1021 is stopped, starting instead of rebooting
  -> Starting VM 1021
[Attempt 1] Remediating k8s-worker3.lab.local (VM 1022)
  -> VM 1022 is stopped, starting instead of rebooting
  -> Starting VM 1022
```

**4. CoreDNS stayed up (on masters):**
```
coredns-74b76c898f-mwjq6   Running   k8s-master1.lab.local
coredns-74b76c898f-rr6s9   Running   k8s-master3.lab.local
coredns-74b76c898f-94k7p   Terminating   k8s-master2.lab.local  # evicted correctly
```

**5. Apps recovered after DNS stabilized:**
```
# Initial DNS timeout (CoreDNS on master2 terminating)
[ERROR] agent.auth.handler: error authenticating: dial tcp: lookup vault.lab.local: i/o timeout

# DNS working via master1/master3 CoreDNS
kubectl exec vault-agent-injector -- nslookup vault.lab.local
Name:    vault.lab.local
Address: 10.0.62.100

# Apps recovered
wordpress-6d4f6bbd46-ghspb   2/2     Running
wordpress-6d4f6bbd46-mmq2q   2/2     Running
```

**Note:** Brief DNS hiccup during CoreDNS pod eviction from master2 is expected. Pods retried and succeeded once CoreDNS endpoints updated to master1/master3.

### kube-controller-manager Logs

During test, controller-manager had leader election issues:
```
E0418 19:44:19 "Error retrieving lease lock" err="context deadline exceeded"
E0418 19:45:15 "Error retrieving lease lock" err="connection refused"
```

This may have prevented proper taint application.

---

## Manual Workaround

Adding `NoExecute` taint manually triggers eviction:

```bash
kubectl taint nodes <node-name> node.kubernetes.io/unreachable:NoExecute
```

**Result:** Pod eviction worked within tolerationSeconds (300s).

---

## Root Cause - IDENTIFIED

### Confirmed Root Cause: PartialDisruption Mode Rate-Limiting

When too many nodes fail simultaneously (>55% by default), Kubernetes enters **PartialDisruption** mode and rate-limits NoExecute taint application to prevent cascading failures.

### Evidence from DR Test 3 (2026-04-18 ~23:42)

**Test scenario:** Shutdown master2 + all 3 workers (4 of 6 nodes = 66%)

**Taints observed after shutdown:**

| Node | NoExecute | NoSchedule | Comment |
|------|-----------|------------|---------|
| master1 | - | Yes (control-plane) | UP |
| master2 | NO | Yes,Yes | DOWN - only NoSchedule! |
| master3 | - | Yes (control-plane) | UP |
| worker1 | YES | Yes | DOWN - got NoExecute |
| worker2 | NO | Yes | DOWN - only NoSchedule! |
| worker3 | NO | Yes | DOWN - only NoSchedule! |

**Only worker1 got NoExecute.** Same pattern as Test 2 (where only worker2 got NoExecute).

### Controller-Manager Logs (Evidence)

```
I0418 21:42:08 node_lifecycle_controller.go:460] "Starting node controller"
I0418 21:42:08 taint_eviction.go:283] "Starting" controller="taint-eviction-controller"
I0418 21:43:01 node_lifecycle_controller.go:1080] "Controller detected that zone is now in new state" zone="" newState="PartialDisruption"
```

**Key line:** `newState="PartialDisruption"` - Controller entered rate-limiting mode.

**5 minutes later, only worker1 pods evicted:**
```
I0418 21:47:59 taint_eviction.go:111] "Deleting pod" pod="monitoring/prometheus-kube-prometheus-stack-prometheus-0"
I0418 21:47:59 taint_eviction.go:111] "Deleting pod" pod="kube-system/metrics-server-84f68d86c5-wqsmt"
I0418 21:47:59 taint_eviction.go:111] "Deleting pod" pod="kube-system/csi-nfs-controller-64ff9db975-vhqxb"
I0418 21:47:59 taint_eviction.go:111] "Deleting pod" pod="monitoring/kube-prometheus-stack-grafana-7bc777d646-w6pzq"
```

All evicted pods were from worker1 (the only node with NoExecute). Other nodes' pods NOT evicted.

### Why This Breaks Self-Healing

```
Scenario: master2 (has remediation) + all workers down

Current behavior:
├── master2 → Only NoSchedule → Remediation NOT evicted
├── worker1 → NoExecute → Pods evicted, but nowhere to go (all workers down)
├── worker2 → Only NoSchedule → Pods NOT evicted
├── worker3 → Only NoSchedule → Pods NOT evicted
│
└── Result: Remediation stuck on master2
             Cannot reschedule to master1 or master3
             Workers never recover
             CLUSTER STUCK
```

### Kubernetes PartialDisruption Behavior

**Default threshold:** `--unhealthy-zone-threshold=0.55` (55%)

| Nodes Down | Percentage | Mode | Behavior |
|------------|------------|------|----------|
| 3/6 | 50% | Normal | All get NoExecute immediately |
| 4/6 | 66% | PartialDisruption | Rate-limited, only 1 gets NoExecute |
| 5/6 | 83% | PartialDisruption | Rate-limited |

**Current config (no override):**
```yaml
- command:
  - kube-controller-manager
  - --controllers=*,bootstrapsigner,tokencleaner
  # --unhealthy-zone-threshold not set, defaults to 0.55
```

### Why DNS Fix Alone Didn't Solve It

CoreDNS HA fix (issue #44) ensures controller-manager keeps leadership. But PartialDisruption mode is independent of DNS - it triggers based on percentage of unhealthy nodes.

Even with DNS working perfectly, 4/6 nodes down = PartialDisruption = rate-limited eviction.

### Proposed Fix (Pending Test)

Raise threshold so PartialDisruption triggers later:

```yaml
# /etc/kubernetes/manifests/kube-controller-manager.yaml
- command:
  - kube-controller-manager
  - --allocate-node-cidrs=true
  - --authentication-kubeconfig=/etc/kubernetes/controller-manager.conf
  - --authorization-kubeconfig=/etc/kubernetes/controller-manager.conf
  - --bind-address=127.0.0.1
  - --client-ca-file=/etc/kubernetes/pki/ca.crt
  - --cluster-cidr=10.244.0.0/16
  - --cluster-name=kubernetes
  - --cluster-signing-cert-file=/etc/kubernetes/pki/ca.crt
  - --cluster-signing-key-file=/etc/kubernetes/pki/ca.key
  - --controllers=*,bootstrapsigner,tokencleaner
  - --kubeconfig=/etc/kubernetes/controller-manager.conf
  - --leader-elect=true
  - --requestheader-client-ca-file=/etc/kubernetes/pki/front-proxy-ca.crt
  - --root-ca-file=/etc/kubernetes/pki/ca.crt
  - --service-account-private-key-file=/etc/kubernetes/pki/sa.key
  - --service-cluster-ip-range=10.96.0.0/12
  - --use-service-account-credentials=true
  - --unhealthy-zone-threshold=0.8    # ADD THIS LINE
```

**With threshold 0.8:**
| Nodes Down | Percentage | Mode | Behavior |
|------------|------------|------|----------|
| 4/6 | 66% < 80% | Normal | All get NoExecute immediately |
| 5/6 | 83% > 80% | PartialDisruption | Rate-limited (acceptable) |

**Apply to ALL masters** - each has its own controller-manager static pod.

---

## Solution

### Part 1: DNS HA (APPLIED)

CoreDNS fix ensures controller-manager maintains leadership. See issue #44.
**Status:** Applied and verified.

### Part 2: Raise Unhealthy Zone Threshold (APPLIED & VERIFIED)

Edit `/etc/kubernetes/manifests/kube-controller-manager.yaml` on ALL masters:

```yaml
- --unhealthy-zone-threshold=0.8
```

**Status:** Applied and verified in DR Test 4.

### Part 3: Manual Emergency Command

If NoExecute taint is not applied automatically:
```bash
# Apply to all NotReady nodes at once
for node in $(kubectl get nodes -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Ready")].status=="Unknown")].metadata.name}'); do
  kubectl taint nodes $node node.kubernetes.io/unreachable:NoExecute --overwrite 2>/dev/null
done
```

---

## Related

- `disaster-recovery/tmp-partial-worker-loss.md` - DR Test where issue was discovered
- `troubleshooting/kubernetes/44-coredns-ha-masters.md` - DNS HA fix (may resolve this)

---

## Timeline

| Time | Event |
|------|-------|
| 2026-04-18 20:25 | DR Test 2 started |
| 2026-04-18 20:30 | Noticed pods not evicting |
| 2026-04-18 21:00 | Identified NoSchedule instead of NoExecute |
| 2026-04-18 22:30 | Confirmed manual NoExecute taint works |
| 2026-04-18 22:35 | Eviction successful with manual taint |
| 2026-04-18 ~23:30 | CoreDNS HA fix applied (issue #44) |
| 2026-04-18 ~23:42 | DR Test 3 started (master2 + all workers) |
| 2026-04-18 ~23:44 | Only worker1 got NoExecute, others NoSchedule only |
| 2026-04-18 ~23:50 | Identified PartialDisruption mode as root cause |
| 2026-04-18 ~23:55 | Identified fix: --unhealthy-zone-threshold=0.8 |
| 2026-04-19 ~00:05 | Applied fix to all 3 masters |
| 2026-04-19 ~00:09 | DR Test 4: ALL nodes got NoExecute |
| 2026-04-19 ~00:10 | Remediation evicted from master2, rescheduled to master3 |
| 2026-04-19 ~00:15 | Remediation detected 3 unhealthy workers |
| 2026-04-19 ~00:15 | Workers started automatically |
| 2026-04-19 ~00:20 | All apps recovered (MariaDB, WordPress) |
| 2026-04-19 | **RESOLVED** |
