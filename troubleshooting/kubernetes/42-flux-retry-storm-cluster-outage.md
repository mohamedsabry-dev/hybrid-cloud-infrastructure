# TS-K8S-042 | 2026-04-18 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / FluxCD / Helm / etcd
Sub-techs: HelmRelease retry, pod anti-affinity, rolling update, etcd leader election,
           API server health, kube-prometheus-stack
Environment: DEV k8s-dev cluster | 3 masters + 3 workers | Flux GitOps
Duration: ~45 minutes
Severity: Critical — full cluster outage
Re-opened: No

_____________________________________________________________________

[Issue Description]
Pushed a Grafana helm-release change (Alertmanager datasource config). The rollout
got stuck because of `requiredDuringSchedulingIgnoredDuringExecution` anti-affinity
with 3 replicas on exactly 3 workers. Flux kept retrying the failed Helm upgrade
in a tight loop, each retry hammering the API servers with patch operations. Within
minutes, etcd destabilized, all 3 API servers went unhealthy, and the entire cluster
became unresponsive. WordPress lost database connectivity. Two nodes needed physical
reboot.

_____________________________________________________________________

[Analysis]

# Why the rollout got stuck

I had Grafana configured with `required` anti-affinity and 3 replicas across 3 workers:

```yaml
grafana:
  replicas: 3
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              app.kubernetes.io/name: grafana
          topologyKey: kubernetes.io/hostname
```

The problem: Kubernetes rolling update creates the NEW pod BEFORE terminating the old one.
With 3 workers fully occupied and masters tainted, the 4th pod had nowhere to go:

  Workers 1-3: blocked (each already has a Grafana pod, anti-affinity = hard requirement)
  Masters 1-3: blocked (control-plane taint)
  Result: 0/6 nodes available → pod stuck Pending forever

Command: kubectl describe pod kube-prometheus-stack-grafana-85cb57d6f4-r8lc9 -n monitoring

Output:
```
Warning  FailedScheduling  20m  default-scheduler
0/6 nodes are available:
  3 node(s) didn't match pod anti-affinity rules,
  3 node(s) had untolerated taint(s).
```

# The Flux retry storm

Helm waited 5 minutes for the rollout, timed out, and reported failure. Flux saw
the failure and immediately retried. Each retry was a full Helm upgrade — patching
every ServiceMonitor, ConfigMap, and Deployment in kube-prometheus-stack. That's
heavy API server load per attempt, and Flux was doing it back-to-back with no backoff.

Command: kubectl get helmrelease kube-prometheus-stack -n monitoring

Output:
```
NAME                    AGE   READY   STATUS
kube-prometheus-stack   8d    False   Helm upgrade failed for release monitoring/kube-prometheus-stack
                                      with chart kube-prometheus-stack@82.18.0:
                                      timeout waiting for: [Deployment/monitoring/kube-prometheus-stack-grafana status: 'InProgress']
```

Evidence from Helm logs — one retry cycle patching 9 ServiceMonitors in under a second:
```
2026-04-18T09:03:23.190Z: Patched resource: {"gvk":"monitoring.coreos.com/v1, Kind=ServiceMonitor","name":"kube-prometheus-stack-coredns"}
2026-04-18T09:03:23.203Z: Patched resource: {"gvk":"monitoring.coreos.com/v1, Kind=ServiceMonitor","name":"kube-prometheus-stack-apiserver"}
2026-04-18T09:03:23.234Z: Patched resource: {"gvk":"monitoring.coreos.com/v1, Kind=ServiceMonitor","name":"kube-prometheus-stack-kube-controller-manager"}
2026-04-18T09:03:23.247Z: Patched resource: {"gvk":"monitoring.coreos.com/v1, Kind=ServiceMonitor","name":"kube-prometheus-stack-kube-etcd"}
2026-04-18T09:03:23.260Z: Patched resource: {"gvk":"monitoring.coreos.com/v1, Kind=ServiceMonitor","name":"kube-prometheus-stack-kube-proxy"}
2026-04-18T09:03:23.273Z: Patched resource: {"gvk":"monitoring.coreos.com/v1, Kind=ServiceMonitor","name":"kube-prometheus-stack-kube-scheduler"}
2026-04-18T09:03:23.317Z: Patched resource: {"gvk":"monitoring.coreos.com/v1, Kind=ServiceMonitor","name":"kube-prometheus-stack-kubelet"}
2026-04-18T09:03:23.332Z: Patched resource: {"gvk":"monitoring.coreos.com/v1, Kind=ServiceMonitor","name":"kube-prometheus-stack-operator"}
2026-04-18T09:03:23.345Z: Patched resource: {"gvk":"monitoring.coreos.com/v1, Kind=ServiceMonitor","name":"kube-prometheus-stack-prometheus"}
2026-04-18T09:08:23.782Z: warning: upgrade failed: {"error":{},"name":"kube-prometheus-stack"}
```

# etcd destabilization

The retry loop flooded etcd with writes. Leader election started failing:

```
{"level":"warn","ts":"2026-04-18T10:01:37.571Z","msg":"retrying of unary invoker failed",
  "method":"/etcdserverpb.KV/Range","error":"rpc error: code = Unavailable desc = etcdserver: leader changed"}
```

API server gRPC connections to etcd started dropping:
```
W0418 10:01:24.559021  1 logging.go:55] [core] grpc: addrConn.createTransport failed to connect to
  {Addr: "127.0.0.1:2379"}. Err: connection error: desc = "transport: authentication handshake failed: context canceled"
```

Cache reflectors expired waiting for events that etcd couldn't deliver:
```
I0418 10:01:34.552942  1 reflector.go:1159] "Warning: event bookmark expired"
  err="storage/cacher.go:/secrets: awaiting required bookmark event for initial events stream, no events received for 10.001005431s"
```

Then deadline exceeded — etcd effectively stopped serving:
```
{"level":"warn","ts":"2026-04-18T10:10:13.138Z","msg":"retrying of unary invoker failed",
  "method":"/etcdserverpb.KV/Range","error":"rpc error: code = DeadlineExceeded desc = context deadline exceeded"}
```

# API servers went down

All 3 API servers became 0/1 Ready:

Command: kubectl get pods -n kube-system | grep api

Output:
```
kube-apiserver-k8s-master1.lab.local   0/1   Running   47 (3m22s ago)   22d
kube-apiserver-k8s-master2.lab.local   0/1   Running   43 (109s ago)    22d
kube-apiserver-k8s-master3.lab.local   0/1   Running   51 (2m45s ago)   22d
```

kubectl commands were either timing out or returning auth errors — the API servers
couldn't reach etcd to check authorization:

```
Error from server (Forbidden): pods is forbidden: User "kubernetes-admin" cannot list resource "pods"
Error from server (InternalError): Authorization error (user=kube-apiserver-kubelet-client, verb=get, resource=nodes)
```

# Application impact cascade

The cascade went: API servers unstable → CoreDNS watches fail → kube-proxy can't
update iptables → service routing goes stale → WordPress can't resolve MariaDB:

```
Warning: mysqli_real_connect(): (HY000/2002): Connection refused
Error establishing a database connection
```

Two nodes (master2, worker2) went NotReady and stopped responding to SSH entirely.

_____________________________________________________________________

[Final Root Cause]
Two things combined:

1. **Anti-affinity deadlock** — `required` anti-affinity with replicas == available nodes
   means rolling updates can never schedule the new pod. The rollout gets stuck
   forever waiting for a node that will never become available.

2. **Flux has no circuit breaker** — Flux retries failed HelmReleases immediately
   with no backoff. Each retry is a full Helm upgrade (heavy API server load).
   Rapid-fire retries overwhelmed etcd and cascaded into full cluster failure.

Either problem alone would have been manageable. The anti-affinity deadlock
by itself is just a stuck rollout. The Flux retry behavior by itself is fine
for transient failures. Combined, they created a feedback loop that took down
the cluster.

_____________________________________________________________________

[Final Solution]

# Step 1: Stop the bleeding — suspend Flux

```
flux suspend kustomization --all
flux suspend helmrelease --all -A
```

Cluster immediately started recovering. This confirmed the retry loop was the cause.

# Step 2: Physical reboot of unresponsive nodes

master2 and worker2 didn't respond to SSH — required physical power cycle.

# Step 3: Verify cluster health

```
kubectl get nodes
NAME                    STATUS   ROLES           AGE   VERSION
k8s-master1.lab.local   Ready    control-plane   22d   v1.35.3
k8s-master2.lab.local   Ready    control-plane   22d   v1.35.3
k8s-master3.lab.local   Ready    control-plane   22d   v1.35.3
k8s-worker1.lab.local   Ready    <none>          22d   v1.35.3
k8s-worker2.lab.local   Ready    <none>          22d   v1.35.3
k8s-worker3.lab.local   Ready    <none>          22d   v1.35.3
```

# Step 4: Fix the anti-affinity

Changed `required` → `preferred` with weight 100. This still spreads pods across
nodes but allows temporary co-location during rollouts:

```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - podAffinityTerm:
        labelSelector:
          matchLabels:
            app.kubernetes.io/name: grafana
        topologyKey: kubernetes.io/hostname
      weight: 100
```

# Step 5: Resume Flux

```
flux resume kustomization --all
flux suspend helmrelease kube-prometheus-stack -n monitoring
sleep 2
flux resume helmrelease kube-prometheus-stack -n monitoring
```

Result:
```
✔ HelmRelease kube-prometheus-stack reconciliation completed
✔ applied revision 82.18.0
```

Grafana pods after fix — two on the same node, which is fine with `preferred`:
```
kube-prometheus-stack-grafana-7ccfbf6cc4-5nnhl   4/4   Running   k8s-worker2.lab.local
kube-prometheus-stack-grafana-7ccfbf6cc4-8hpkr   4/4   Running   k8s-worker1.lab.local
kube-prometheus-stack-grafana-7ccfbf6cc4-ljh5z   4/4   Running   k8s-worker1.lab.local
```

Verified: Yes — all pods running, all nodes Ready, HelmRelease reconciled.

_____________________________________________________________________

[Risk Level] CRITICAL

A single misconfigured anti-affinity value + Flux's default retry behavior
took down the entire cluster for 45 minutes. The fix is simple (preferred
instead of required), but the blast radius of getting it wrong is total.

_____________________________________________________________________

[References]
- TS-K8S-036 — Grafana anti-affinity rollout stuck (the isolated rollout issue)
- TS-K8S-041 — PrometheusRule not picked up (discovered during same session)
- TS-K8S-040 — HPA memory scaling behavior (discovered during same session)
- TS-K8S-038 — QEMU guest agent CPU loop (discovered during same session)
- disaster-recovery/worker-2of3-down.md — related DR test for node failure scenarios
