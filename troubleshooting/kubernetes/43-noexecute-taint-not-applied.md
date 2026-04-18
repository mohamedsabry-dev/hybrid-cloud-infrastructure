# Issue: NoExecute Taint Not Applied Automatically to Unreachable Nodes

**Status:** OPEN - Investigation Required
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

### Inconsistent Behavior Across Nodes

During DR test, different nodes got different taints:

| Node | NoExecute | NoSchedule |
|------|-----------|------------|
| master3 | ❌ NO | ✅ Yes |
| worker1 | ❌ NO | ✅ Yes |
| worker2 | ✅ YES | ✅ Yes |
| worker3 | ❌ NO | ✅ Yes |

Only worker2 got `NoExecute` taint. Others only got `NoSchedule`.

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

## Root Cause Investigation

### Possible Causes

1. **kube-controller-manager leader election failure** - DNS was down, controller couldn't maintain leadership
2. **Feature gate disabled** - TaintBasedEvictions might be disabled
3. **kubeadm configuration** - Non-standard settings
4. **Race condition** - Nodes coming up/down rapidly

### Investigation Steps

```bash
# Check controller-manager config
cat /etc/kubernetes/manifests/kube-controller-manager.yaml | grep -iE "taint|evict|feature"

# Check feature gates
kubectl get cm -n kube-system kubeadm-config -o yaml | grep -i feature

# Check controller-manager logs during node failure
kubectl logs -n kube-system kube-controller-manager-k8s-master1.lab.local | grep -i taint
```

---

## Solution

### Immediate Fix (Manual)
```bash
# When node goes NotReady, manually add NoExecute taint
kubectl taint nodes <node-name> node.kubernetes.io/unreachable:NoExecute
```

### Permanent Fix (TBD)
1. Ensure DNS is always available (see issue #44)
2. Investigate kube-controller-manager configuration
3. Consider adding monitoring alert for missing NoExecute taints

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
