# TS-K8S-036 | 2026-04-18 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / Grafana / Pod Scheduling
Sub-techs: podAntiAffinity, required vs preferred, rolling update strategy,
           kube-prometheus-stack, Helm values
Environment: DEV k8s cluster | 3 workers + 3 masters (tainted)
Discovered during: Grafana HelmRelease update
Related: TS-K8S-042 (Flux retry storm — cascaded from incorrect fix of this issue)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Grafana deployment rollout stuck with new pod in `Pending` state. Anti-affinity
rule prevented scheduling when all 3 workers already had a Grafana pod.

```
kubectl get pods -n monitoring | grep grafana
kube-prometheus-stack-grafana-5f6554dcf5-8bqm5   4/4     Running   0    11h
kube-prometheus-stack-grafana-5f6554dcf5-lrvqq   4/4     Running   36   4d11h
kube-prometheus-stack-grafana-5f6554dcf5-mqbk5   4/4     Running   32   4d11h
kube-prometheus-stack-grafana-85cb57d6f4-r8lc9   0/4     Pending   0    19m   # STUCK
```

Alert fired:
```
alertname = KubePodNotReady
pod = kube-prometheus-stack-grafana-85cb57d6f4-r8lc9
description = Pod has been in a non-ready state for more than 15 minutes
```

_____________________________________________________________________

[Analysis]

# Step 1: Pod describe events

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

3 workers blocked by anti-affinity (each already has 1 Grafana pod), 3 masters
blocked by control-plane taint.

# Step 2: Identified the deadlock

The setup: 3 Grafana replicas, 3 worker nodes, `requiredDuringSchedulingIgnored-
DuringExecution` anti-affinity. Rolling update creates the NEW pod BEFORE
terminating the old one. With all 3 workers occupied and masters tainted, the
4th pod has nowhere to go → stuck Pending forever → rollout never completes.

_____________________________________________________________________

[Final Root Cause]
`required` anti-affinity with replicas == available nodes means rolling updates
can never schedule the new pod. The 4th pod has nowhere to go because all workers
already have one Grafana pod and masters are tainted.

_____________________________________________________________________

[Final Solution]

Changed anti-affinity to `preferred` with weight 100. This still spreads pods
across nodes but allows temporary co-location during rollouts:

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

Cleanup:
```
kubectl delete pod kube-prometheus-stack-grafana-85cb57d6f4-r8lc9 -n monitoring
kubectl rollout status deployment kube-prometheus-stack-grafana -n monitoring
```

File modified: `kubernetes/dev/deployments/apps/monitoring/helm-release.yaml`

WARNING: Applying this fix incorrectly (malformed YAML — missing `podAffinityTerm`
wrapper) caused a major cluster outage. Flux entered a retry loop that overloaded
etcd. Full incident in TS-K8S-042.

Verified: Yes — rollout completes, steady state still spreads 1 pod per worker.

_____________________________________________________________________

[Risk Level] LOW

The fix itself is low risk. But the cascaded incident from the incorrect YAML
was critical — see TS-K8S-042.

_____________________________________________________________________

[References]
- TS-K8S-042 — Flux retry storm cluster outage (cascaded from incorrect fix attempt)
