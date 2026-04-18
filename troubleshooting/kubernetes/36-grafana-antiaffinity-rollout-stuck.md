# Issue: Grafana Rollout Stuck Due to Anti-Affinity

**Status:** RESOLVED
**Date Discovered:** 2026-04-18
**Resolution:** Changed anti-affinity from `required` to `preferred`

---

## Summary

Grafana deployment rollout stuck with new pod in `Pending` state. Anti-affinity rule prevents scheduling when all workers already have a Grafana pod.

---

## Symptoms

```bash
kubectl get pods -n monitoring | grep grafana
```
```
kube-prometheus-stack-grafana-5f6554dcf5-8bqm5   4/4     Running   0    11h
kube-prometheus-stack-grafana-5f6554dcf5-lrvqq   4/4     Running   36   4d11h
kube-prometheus-stack-grafana-5f6554dcf5-mqbk5   4/4     Running   32   4d11h
kube-prometheus-stack-grafana-85cb57d6f4-r8lc9   0/4     Pending   0    19m   # STUCK
```

**Alert fired:**
```
alertname = KubePodNotReady
pod = kube-prometheus-stack-grafana-85cb57d6f4-r8lc9
description = Pod has been in a non-ready state for more than 15 minutes
```

---

## Evidence

**Pod describe events:**
```
Warning  FailedScheduling  20m  default-scheduler
0/6 nodes are available:
  3 node(s) didn't match pod anti-affinity rules,
  3 node(s) had untolerated taint(s).
no new claims to deallocate,
preemption: 0/6 nodes are available:
  3 No preemption victims found for incoming pod,
  3 Preemption is not helpful for scheduling.
```

**Breakdown:**
- 3 workers: blocked by anti-affinity (each already has 1 Grafana pod)
- 3 masters: blocked by taint (`node-role.kubernetes.io/control-plane`)

---

## Root Cause

| Factor | Value |
|--------|-------|
| Grafana replicas | 3 |
| Worker nodes | 3 |
| Anti-affinity type | `requiredDuringSchedulingIgnoredDuringExecution` |
| Rolling update strategy | Creates new pod BEFORE terminating old |

**Scenario:**
1. 3 Grafana pods running on 3 workers (1 per worker)
2. `kubectl rollout restart` triggered
3. Rolling update tries to create 4th pod (new revision)
4. Anti-affinity blocks scheduling on workers (each has 1 pod)
5. Masters blocked by taint
6. 4th pod stuck in `Pending`
7. Rollout never completes

---

## Solution Options

| Option | Pros | Cons |
|--------|------|------|
| Delete old pod manually | Quick fix | Manual intervention each time |
| Change to `preferred` anti-affinity | Allows temporary 2 pods/node | Slightly less HA during rollout |
| Set `maxSurge: 0, maxUnavailable: 1` | Kills before creating | Brief downtime during rollout |
| Add more workers | More capacity | Resource cost |

---

## Chosen Solution

**Change anti-affinity to `preferred`**

This allows temporary co-location of 2 pods on same node during rollout:
- Scheduler prefers spreading but doesn't require it
- Rollout can proceed
- Steady state still has 1 pod per worker

**Helm values:**
```yaml
grafana:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchLabels:
                app.kubernetes.io/name: grafana
            topologyKey: kubernetes.io/hostname
```

---

## ⚠️ WARNING: Cascaded Incident

**Applying this fix incorrectly caused a major cluster outage.**

During the initial fix attempt, the anti-affinity YAML structure was malformed (missing `podAffinityTerm` wrapper). This caused:

1. Flux detected invalid HelmRelease and entered retry loop
2. Retry storm overloaded etcd with rapid reconciliation attempts
3. etcd leader election failures cascaded to API server
4. Cluster became unresponsive
5. Multiple pods entered CrashLoopBackOff

**Full incident documented in:** `troubleshooting/kubernetes/42-flux-retry-storm-cluster-outage.md`

**Lesson learned:** Always validate YAML structure before pushing Helm value changes. Use `helm template` or `kubectl diff` to verify.

---

## Files Modified

- `kubernetes/dev/deployments/apps/monitoring/helm-release.yaml` - Changed anti-affinity from required to preferred

---

## Cleanup After Fix

```bash
# Delete stuck pending pod
kubectl delete pod kube-prometheus-stack-grafana-85cb57d6f4-r8lc9 -n monitoring

# Verify rollout completes
kubectl rollout status deployment kube-prometheus-stack-grafana -n monitoring
```
