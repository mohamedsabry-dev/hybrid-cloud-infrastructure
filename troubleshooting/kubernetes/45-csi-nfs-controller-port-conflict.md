# Issue: CSI NFS Controller Pod Port Conflict - Both Pods on Same Node

**Status:** RESOLVED
**Date Discovered:** 2026-04-18
**Severity:** Medium
**Discovered During:** Post-DR Test Recovery

---

## Summary

CSI NFS controller deployment (replicas=2) scheduled both pods on the same worker node, causing liveness probe port conflict and CrashLoopBackOff.

---

## Symptoms

```bash
kubectl get pods -n kube-system | grep csi-nfs-controller
```

```
csi-nfs-controller-8455c76c5f-8k7xv   4/5   CrashLoopBackOff   52 (2m4s ago)   107m   k8s-worker3.lab.local
csi-nfs-controller-8455c76c5f-9p4tt   5/5   Running            28 (5m17s ago) 159m   k8s-worker3.lab.local
```

Both pods on worker3 - one crashing, one running.

---

## Root Cause

1. CSI NFS controller uses liveness probe on port `127.0.0.1:29652`
2. Deployment had `nodeAffinity` (run on workers only) but NO `podAntiAffinity`
3. During DR test chaos, workers 1 & 2 were down
4. Both controller pods scheduled to worker3 (only available worker)
5. Second pod can't bind to port 29652 - already in use by first pod
6. Result: CrashLoopBackOff

### Error from logs

```
listen tcp 127.0.0.1:29652: bind: address already in use
```

---

## Diagram

```
Before Fix (no podAntiAffinity):

┌─────────┐ ┌─────────┐ ┌─────────┐
│ worker1 │ │ worker2 │ │ worker3 │
│  (down) │ │  (down) │ │ csi-1   │ ← Both here!
│         │ │         │ │ csi-2   │   Port conflict!
└─────────┘ └─────────┘ └─────────┘

After Fix (with podAntiAffinity):

┌─────────┐ ┌─────────┐ ┌─────────┐
│ worker1 │ │ worker2 │ │ worker3 │
│ csi-1   │ │ csi-2   │ │         │ ← Spread across nodes
└─────────┘ └─────────┘ └─────────┘
```

---

## Fix Applied

Added `podAntiAffinity` to CSI NFS controller helm values.

**File:** `kubernetes/dev/deployments/infrastructure/storage/nfs-csi-driver.yaml`

**Change:**

```yaml
controller:
  replicas: 2
  priorityClassName: system-cluster-critical
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: node-role.kubernetes.io/control-plane
                operator: DoesNotExist
    # NEW: Force pods to different nodes
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              app: csi-nfs-controller
          topologyKey: kubernetes.io/hostname
```

---

## Explanation

| Rule | Purpose |
|------|---------|
| `nodeAffinity` | "Run on worker nodes only" (not control-plane) |
| `podAntiAffinity` | "Don't run on a node that already has another csi-nfs-controller pod" |
| `topologyKey: kubernetes.io/hostname` | "Spread by hostname" = one pod per node |
| `requiredDuringScheduling` | Hard requirement, not just preference |

---

## Verification

After Flux applies the change:

```bash
# Check pods are on different nodes
kubectl get pods -n kube-system -l app=csi-nfs-controller -o wide

# Expected: Each pod on a different worker
NAME                                  READY   NODE
csi-nfs-controller-xxx-aaa            5/5     k8s-worker1.lab.local
csi-nfs-controller-xxx-bbb            5/5     k8s-worker2.lab.local
```

---

## Related

- Same issue pattern as Grafana antiAffinity rollout (#36)
- Discovered during DR Test 2 recovery phase

---

## Timeline

| Time | Event |
|------|-------|
| 2026-04-18 ~20:30 | DR Test 2 - workers 1 & 2 shutdown |
| 2026-04-18 ~22:00 | Workers recovered, but both CSI pods on worker3 |
| 2026-04-18 ~23:30 | Identified port conflict as root cause |
| 2026-04-18 ~23:35 | Added podAntiAffinity fix |
| 2026-04-18 | RESOLVED via Flux |

---

## Lesson Learned

Any deployment with replicas > 1 that uses host-bound resources (ports, paths) **must** have podAntiAffinity to prevent scheduling conflicts.
