# Incident Report: Flux Retry Storm Causing Cluster-Wide Outage

**Date:** 2026-04-18
**Duration:** ~45 minutes (10:00 - 10:45 UTC approximately)
**Severity:** Critical (P1)
**Status:** RESOLVED
**Workaround Applied:** Physical reboot of affected nodes (master2, worker2)
**Follow-up:** Incident repeat planned for controlled simulation and deeper investigation

---

## Executive Summary

A stuck Grafana rollout caused by `requiredDuringSchedulingIgnoredDuringExecution` pod anti-affinity triggered a Helm upgrade timeout. Flux CD continuously retried the failed upgrade, creating a retry storm that overwhelmed etcd and the Kubernetes API servers. This cascaded into a cluster-wide outage affecting all applications, including WordPress losing database connectivity.

**Root Cause:** Pod anti-affinity misconfiguration + Flux aggressive retry behavior

**Impact:**
- All 3 API servers became unhealthy (0/1 Ready)
- etcd leader election destabilized
- All kubectl commands failed or timed out
- WordPress application showed database connection errors
- 2 nodes marked NotReady (master2, worker2)
- Required physical reboot of master2 and worker2

---

## Timeline

| Time (approx) | Event |
|---------------|-------|
| T-hours | Grafana configured with 3 replicas + `required` anti-affinity on 3 workers |
| T-30min | Changes made to helm-release.yaml (Alertmanager datasource, other configs) |
| T-20min | Helm upgrade triggered, rollout creates 4th Grafana pod |
| T-20min | 4th pod stuck in Pending (no node available - anti-affinity blocks all workers, taints block masters) |
| T-15min | Helm upgrade timeout (5 minutes) |
| T-15min | Flux retries immediately |
| T-10min | Retry loop begins - multiple timeouts |
| T-5min | etcd starts showing leader election issues |
| T-0 | API servers fail health checks, kubectl commands fail |
| T+5min | Flux suspended, cluster begins recovery |
| T+15min | master2 and worker2 still NotReady, required physical reboot |
| T+30min | All nodes Ready |
| T+45min | HelmRelease reconciled successfully |

---

## Detailed Analysis

### Phase 1: The Setup (Anti-Affinity Misconfiguration)

**Configuration in `helm-release.yaml`:**
```yaml
grafana:
  replicas: 3
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:  # <-- THE PROBLEM
        - labelSelector:
            matchLabels:
              app.kubernetes.io/name: grafana
          topologyKey: kubernetes.io/hostname
```

**Cluster topology:**
- 3 master nodes (tainted: `node-role.kubernetes.io/control-plane`)
- 3 worker nodes (no taints)
- Grafana replicas: 3

**The math:**
```
Workers available: 3
Grafana pods: 3 (one per worker)
Anti-affinity: REQUIRED - no two Grafana pods on same node

During rollout:
- Kubernetes rolling update creates NEW pod BEFORE terminating old
- New pod (4th) needs a node
- Worker1: blocked (has Grafana pod)
- Worker2: blocked (has Grafana pod)
- Worker3: blocked (has Grafana pod)
- Master1/2/3: blocked (control-plane taint)
- Result: 0/6 nodes available
```

**Evidence - Pod describe:**
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

### Phase 2: The Stuck Rollout

**Observed state:**
```bash
kubectl get pods -n monitoring | grep grafana
```
```
kube-prometheus-stack-grafana-5f6554dcf5-8bqm5   4/4     Running   0    11h
kube-prometheus-stack-grafana-5f6554dcf5-lrvqq   4/4     Running   36   4d11h
kube-prometheus-stack-grafana-5f6554dcf5-mqbk5   4/4     Running   32   4d11h
kube-prometheus-stack-grafana-85cb57d6f4-r8lc9   0/4     Pending   0    19m   # STUCK
```

Multiple ReplicaSets coexisting:
- `5f6554dcf5` - old revision (3 running pods)
- `85cb57d6f4` - new revision (1 pending pod)
- `7ccfbf6cc4` - another revision (created during retry attempts)

### Phase 3: Helm Timeout and Flux Retry Loop

**HelmRelease status during incident:**
```
NAME                    AGE   READY   STATUS
kube-prometheus-stack   8d    False   Helm upgrade failed for release monitoring/kube-prometheus-stack
                                      with chart kube-prometheus-stack@82.18.0:
                                      timeout waiting for: [Deployment/monitoring/kube-prometheus-stack-grafana status: 'InProgress']
```

**The retry loop mechanism:**
```
1. Flux detects HelmRelease not Ready
2. Flux triggers Helm upgrade
3. Helm waits for Deployment rollout (default 5 min timeout)
4. Rollout stuck (pending pod can't schedule)
5. Helm times out, marks upgrade failed
6. Flux sees failure, schedules immediate retry
7. GOTO step 2

Each iteration:
- Helm upgrade = heavy API server operations
- Patch multiple resources (ServiceMonitors, ConfigMaps, etc.)
- Check deployment status repeatedly
- Write events to etcd
- Flux controller logging and status updates
```

**Evidence from Helm logs:**
```
2026-04-18T09:03:23.190338523Z: Patched resource: {"gvk":"monitoring.coreos.com/v1, Kind=ServiceMonitor","name":"kube-prometheus-stack-coredns","namespace":"monitoring"}
2026-04-18T09:03:23.203449644Z: Patched resource: {"gvk":"monitoring.coreos.com/v1, Kind=ServiceMonitor","name":"kube-prometheus-stack-apiserver","namespace":"monitoring"}
2026-04-18T09:03:23.234311106Z: Patched resource: {"gvk":"monitoring.coreos.com/v1, Kind=ServiceMonitor","name":"kube-prometheus-stack-kube-controller-manager","namespace":"monitoring"}
2026-04-18T09:03:23.247151781Z: Patched resource: {"gvk":"monitoring.coreos.com/v1, Kind=ServiceMonitor","name":"kube-prometheus-stack-kube-etcd","namespace":"monitoring"}
2026-04-18T09:03:23.26013864Z: Patched resource: {"gvk":"monitoring.coreos.com/v1, Kind=ServiceMonitor","name":"kube-prometheus-stack-kube-proxy","namespace":"monitoring"}
2026-04-18T09:03:23.273629321Z: Patched resource: {"gvk":"monitoring.coreos.com/v1, Kind=ServiceMonitor","name":"kube-prometheus-stack-kube-scheduler","namespace":"monitoring"}
2026-04-18T09:03:23.317997634Z: Patched resource: {"gvk":"monitoring.coreos.com/v1, Kind=ServiceMonitor","name":"kube-prometheus-stack-kubelet","namespace":"monitoring"}
2026-04-18T09:03:23.332140685Z: Patched resource: {"gvk":"monitoring.coreos.com/v1, Kind=ServiceMonitor","name":"kube-prometheus-stack-operator","namespace":"monitoring"}
2026-04-18T09:03:23.345281081Z: Patched resource: {"gvk":"monitoring.coreos.com/v1, Kind=ServiceMonitor","name":"kube-prometheus-stack-prometheus","namespace":"monitoring"}
2026-04-18T09:08:23.782585122Z: warning: upgrade failed: {"error":{},"name":"kube-prometheus-stack"}
```

### Phase 4: etcd Destabilization

**API server logs showing etcd connection failures:**
```
W0418 10:01:24.559021       1 logging.go:55] [core] [Channel #27 SubChannel #28]grpc: addrConn.createTransport failed to connect to {Addr: "127.0.0.1:2379", ServerName: "127.0.0.1:2379", ...}. Err: connection error: desc = "transport: authentication handshake failed: context canceled"

W0418 10:01:24.565038       1 logging.go:55] [core] [Channel #31 SubChannel #32]grpc: addrConn.createTransport failed to connect to {Addr: "127.0.0.1:2379", ...}. Err: connection error: desc = "transport: Error while dialing: dial tcp 127.0.0.1:2379: operation was canceled"
```

**etcd leader election issues:**
```
{"level":"warn","ts":"2026-04-18T10:01:37.571657Z","logger":"etcd-client","caller":"v3@v3.6.5/retry_interceptor.go:65","msg":"retrying of unary invoker failed","target":"etcd-endpoints://0xc0010fa960/127.0.0.1:2379","method":"/etcdserverpb.KV/Range","attempt":0,"error":"rpc error: code = Unavailable desc = etcdserver: leader changed"}

{"level":"warn","ts":"2026-04-18T10:01:37.571810Z","logger":"etcd-client","caller":"v3@v3.6.5/retry_interceptor.go:65","msg":"retrying of unary invoker failed","target":"etcd-endpoints://0xc0010fb0e0/127.0.0.1:2379","method":"/etcdserverpb.KV/Range","attempt":0,"error":"rpc error: code = Unavailable desc = etcdserver: leader changed"}
```

**Cache/reflector warnings:**
```
I0418 10:01:34.552942       1 reflector.go:1159] "Warning: event bookmark expired" err="storage/cacher.go:/apiextensions.k8s.io/customresourcedefinitions: awaiting required bookmark event for initial events stream, no events received for 10.000369431s"
I0418 10:01:34.585352       1 reflector.go:1159] "Warning: event bookmark expired" err="storage/cacher.go:/secrets: awaiting required bookmark event for initial events stream, no events received for 10.001005431s"
I0418 10:01:34.593861       1 reflector.go:1159] "Warning: event bookmark expired" err="storage/cacher.go:/configmaps: awaiting required bookmark event for initial events stream, no events received for 10.000777504s"
```

**Deadline exceeded errors:**
```
{"level":"warn","ts":"2026-04-18T10:10:13.138910Z","logger":"etcd-client","caller":"v3@v3.6.5/retry_interceptor.go:65","msg":"retrying of unary invoker failed","target":"etcd-endpoints://0xc0005ed680/127.0.0.1:2379","method":"/etcdserverpb.KV/Range","attempt":0,"error":"rpc error: code = DeadlineExceeded desc = context deadline exceeded"}
```

### Phase 5: API Server Failure

**All 3 API servers became unhealthy:**
```bash
kubectl get pods -n kube-system | grep api
```
```
kube-apiserver-k8s-master1.lab.local   0/1   Running   47 (3m22s ago)   22d
kube-apiserver-k8s-master2.lab.local   0/1   Running   43 (109s ago)    22d
kube-apiserver-k8s-master3.lab.local   0/1   Running   51 (2m45s ago)   22d
```

**kubectl commands failing:**
```bash
kubectl top pods -n monitoring --containers
```
```
Error from server (InternalError): an error on the server ("Internal Server Error: \"/apis/metrics.k8s.io/v1beta1/namespaces/monitoring/pods/containers\": Post \"https://10.96.0.1:443/apis/authorization.k8s.io/v1/subjectaccessreviews?timeout=10s\": net/http: request canceled (Client.Timeout exceeded while awaiting headers)") has prevented the request from succeeding
```

```bash
kubectl get pods -n monitoring
```
```
Error from server (Forbidden): pods is forbidden: User "kubernetes-admin" cannot list resource "pods" in API group "" in the namespace "monitoring"
```

**Authorization errors:**
```
Error from server (InternalError): Internal error occurred: Authorization error (user=kube-apiserver-kubelet-client, verb=get, resource=nodes, subresource=proxy)
```

### Phase 6: Application Impact

**WordPress showing database connection error:**
```
Warning: mysqli_real_connect(): (HY000/2002): Connection refused in /var/www/html/wp-includes/class-wpdb.php on line 1994
Connection refused

Error establishing a database connection
This either means that the username and password information in your wp-config.php file is incorrect or that contact with the database server at mariadb-svc.database.svc.cluster.local could not be established.
```

**Cascade explanation:**
```
API servers unstable
    ↓
CoreDNS can't get updates from API (watches fail)
    ↓
kube-proxy can't update iptables rules (Endpoints watch fails)
    ↓
Service ClusterIP routing becomes stale
    ↓
DNS resolution for services may fail
    ↓
WordPress can't resolve/reach mariadb-svc.database.svc.cluster.local
    ↓
Database connection refused
```

**Nodes marked NotReady:**
```bash
kubectl get nodes
```
```
NAME                    STATUS     ROLES           AGE   VERSION
k8s-master1.lab.local   Ready      control-plane   22d   v1.35.3
k8s-master2.lab.local   NotReady   control-plane   22d   v1.35.3
k8s-master3.lab.local   Ready      control-plane   22d   v1.35.3
k8s-worker1.lab.local   Ready      <none>          22d   v1.35.3
k8s-worker2.lab.local   NotReady   <none>          22d   v1.35.3
k8s-worker3.lab.local   Ready      <none>          22d   v1.35.3
```

---

## Resolution Steps

### Step 1: Suspend Flux (Stop the bleeding)

```bash
flux suspend kustomization --all
flux suspend helmrelease --all -A
```

**Result:** Cluster immediately began recovering. This confirmed Flux retry loop was the cause.

### Step 2: Rolling Reboot of Nodes

Master2 and worker2 were physically unresponsive - required manual reboot.

```bash
# master2 - didn't respond to ssh, required physical/console reboot
# worker2 - was physically down, powered on

# After physical intervention
ssh k8s-master2 "sudo reboot"  # if responsive
ssh k8s-worker2 "sudo reboot"  # if responsive
```

### Step 3: Verify Cluster Health

```bash
kubectl get nodes
```
```
NAME                    STATUS   ROLES           AGE   VERSION
k8s-master1.lab.local   Ready    control-plane   22d   v1.35.3
k8s-master2.lab.local   Ready    control-plane   22d   v1.35.3
k8s-master3.lab.local   Ready    control-plane   22d   v1.35.3
k8s-worker1.lab.local   Ready    <none>          22d   v1.35.3
k8s-worker2.lab.local   Ready    <none>          22d   v1.35.3
k8s-worker3.lab.local   Ready    <none>          22d   v1.35.3
```

```bash
kubectl get pods -n kube-system | grep -E "etcd|api"
```
```
etcd-k8s-master1.lab.local              1/1   Running   36   22d
etcd-k8s-master2.lab.local              1/1   Running   35   22d
etcd-k8s-master3.lab.local              1/1   Running   8    22d
kube-apiserver-k8s-master1.lab.local    1/1   Running   51   22d
kube-apiserver-k8s-master2.lab.local    1/1   Running   45   22d
kube-apiserver-k8s-master3.lab.local    1/1   Running   55   22d
```

### Step 4: Verify Anti-Affinity Fix Was Applied

```bash
kubectl get deployment kube-prometheus-stack-grafana -n monitoring -o yaml | grep -A20 "affinity:"
```
```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:   # <-- FIXED
    - podAffinityTerm:
        labelSelector:
          matchLabels:
            app.kubernetes.io/name: grafana
        topologyKey: kubernetes.io/hostname
      weight: 100
```

### Step 5: Resume Flux and Reconcile

```bash
flux resume kustomization --all

# Reset HelmRelease stale status
flux suspend helmrelease kube-prometheus-stack -n monitoring
sleep 2
flux resume helmrelease kube-prometheus-stack -n monitoring
```

**Result:**
```
✔ HelmRelease kube-prometheus-stack reconciliation completed
✔ applied revision 82.18.0
```

```bash
kubectl get helmrelease kube-prometheus-stack -n monitoring
```
```
NAME                    AGE   READY   STATUS
kube-prometheus-stack   8d    True    Helm upgrade succeeded for release monitoring/kube-prometheus-stack.v12 with chart kube-prometheus-stack@82.18.0
```

### Step 6: Verify Applications Recovered

```bash
kubectl get pods -A | grep -v Running | grep -v Completed
```
```
(no output - all pods running)
```

**Grafana pods with new anti-affinity (allowed on same node):**
```
kube-prometheus-stack-grafana-7ccfbf6cc4-5nnhl   4/4   Running   k8s-worker2.lab.local
kube-prometheus-stack-grafana-7ccfbf6cc4-8hpkr   4/4   Running   k8s-worker1.lab.local
kube-prometheus-stack-grafana-7ccfbf6cc4-ljh5z   4/4   Running   k8s-worker1.lab.local  # <-- 2 on same node OK now
```

---

## Other Issues Discovered During Session

### Issue 1: PrometheusRule Not Picked Up

**Problem:** Custom `ExternalNodeDown` alert not firing despite PrometheusRule applied 13 hours ago.

**Root cause:** Missing `release: kube-prometheus-stack` label required by Prometheus Operator's ruleSelector.

**Evidence:**
```bash
kubectl get prometheus -n monitoring -o jsonpath='{.items[0].spec.ruleSelector}'
# Output: {"matchLabels":{"release":"kube-prometheus-stack"}}
```

**Fix applied:**
```yaml
metadata:
  name: custom-alerts
  namespace: monitoring
  labels:
    release: kube-prometheus-stack  # ADDED
    app.kubernetes.io/name: prometheus
    environment: dev
```

**Verification - both alerts now fire:**
```
alertname = ExternalNodeDown
instance = local-runner.lab.local
role = automation
severity = critical
description = automation node unreachable for 2 minutes

alertname = TargetDown
job = external-nodes
severity = warning
description = 14.29% of the external-nodes/ targets in namespace are down.
```

### Issue 2: HPA Memory Scaling Confusion

**Problem:** WordPress HPA triggered `KubeHpaMaxedOut` alert with 4 pods despite low apparent memory usage.

**Root cause misunderstanding:** HPA calculates percentage against REQUEST, not LIMIT.

**Configuration:**
```yaml
resources:
  requests:
    memory: "128Mi"   # HPA uses THIS
  limits:
    memory: "512Mi"   # HPA ignores this
```

**Actual container usage:**
```bash
kubectl top pods -n apps --containers
```
```
POD                          NAME          MEMORY(bytes)
wordpress-xxx                vault-agent   27Mi
wordpress-xxx                wordpress     76Mi
```

**HPA calculation:**
- WordPress container: ~72Mi average
- HPA: 72Mi / 128Mi request = 56%
- But during video playback: spiked to 186Mi
- 186Mi / 128Mi = 145% → triggered scale-up

**Fix applied:**
```yaml
resources:
  requests:
    memory: "200Mi"  # Increased from 128Mi
```

**New behavior:**
- Idle: 72Mi / 200Mi = 36% (stable)
- Active: 186Mi / 200Mi = 93% (might scale, acceptable)

### Issue 3: QEMU Guest Agent CPU Loop (from earlier session)

**Problem:** qemu-ga process on master3 consuming 98% CPU.

**Resolution:** `systemctl restart qemu-guest-agent`

**Root cause:** Likely stale virtio-serial channel communication issue.

---

## Root Cause Analysis

### Primary Root Cause

**Grafana pod anti-affinity misconfiguration:**
- `requiredDuringSchedulingIgnoredDuringExecution` with 3 replicas on 3 workers
- Rolling update strategy creates new pod BEFORE terminating old
- 4th pod has nowhere to schedule
- Rollout stuck indefinitely

### Secondary Root Cause

**Flux CD aggressive retry behavior:**
- No exponential backoff on HelmRelease failures
- Each retry = full Helm upgrade attempt
- Heavy API server load per attempt
- Rapid succession overwhelms control plane

### Contributing Factors

1. **Limited worker capacity:** Only 3 workers for 3-replica workload with required anti-affinity
2. **Helm upgrade timeout too short:** 5 minutes may not be enough for complex charts
3. **No circuit breaker:** Flux doesn't pause after repeated failures
4. **etcd on same nodes as API servers:** Shared resource contention

---

## Impact Assessment

| Component | Impact | Duration |
|-----------|--------|----------|
| kubectl commands | Failed/timeout | ~30 min |
| API servers | 0/1 Ready | ~20 min |
| etcd | Leader election issues | ~15 min |
| Node status | 2 nodes NotReady | ~25 min |
| WordPress | DB connection refused | ~20 min |
| MariaDB | Pod evicted/restarted | ~10 min |
| Grafana | Stuck rollout | ~45 min (until fix) |
| Developer productivity | Blocked | ~45 min |

---

## Lessons Learned

### 1. Anti-Affinity Strategy

**Wrong:**
```yaml
requiredDuringSchedulingIgnoredDuringExecution  # Blocks rollout
```

**Right:**
```yaml
preferredDuringSchedulingIgnoredDuringExecution  # Allows temporary co-location
  weight: 100  # Still strongly prefers spreading
```

**Rule:** Use `preferred` anti-affinity unless you have more nodes than replicas, or can tolerate brief unavailability during rollouts.

### 2. Flux Retry Behavior

**Problem:** Flux retries immediately on failure, no backoff.

**Mitigation options:**
```yaml
spec:
  install:
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
      remediateLastFailure: false  # Don't keep retrying forever
  timeout: 10m  # Longer timeout for complex charts
```

### 3. Monitoring for Stuck Rollouts

**Add PrometheusRule:**
```yaml
- alert: DeploymentRolloutStuck
  expr: kube_deployment_status_condition{condition="Progressing",status="false"} == 1
  for: 15m
  labels:
    severity: warning
  annotations:
    summary: "Deployment {{ $labels.deployment }} rollout stuck"
```

### 4. Emergency Procedures

**When cluster becomes unresponsive:**
1. First: `flux suspend kustomization --all && flux suspend helmrelease --all -A`
2. Wait 2-3 minutes for etcd to recover
3. Check API server and etcd health
4. If still unhealthy, rolling reboot of masters (one at a time)
5. Resume Flux only after cluster is stable

### 5. HPA Configuration

**HPA uses REQUEST, not LIMIT:**
- Set request to ~70-80% of typical usage
- This gives headroom before scaling triggers
- Limit is just a ceiling, HPA ignores it

### 6. PrometheusRule Labels

**Always include:**
```yaml
labels:
  release: kube-prometheus-stack  # Required for Prometheus Operator to pick up rules
```

Check your Prometheus ruleSelector:
```bash
kubectl get prometheus -n monitoring -o jsonpath='{.items[0].spec.ruleSelector}'
```

---

## Action Items

### Immediate (Completed)

- [x] Change Grafana anti-affinity to `preferred`
- [x] Add `release` label to custom-alerts PrometheusRule
- [x] Increase WordPress memory request to 200Mi
- [x] Document all issues

### Short-term (TODO)

- [ ] Add HelmRelease retry remediation config to limit retries
- [ ] Add `DeploymentRolloutStuck` PrometheusRule
- [ ] Review all deployments with `required` anti-affinity
- [ ] Add etcd monitoring alerts (leader elections, latency)
- [ ] Document emergency Flux suspension procedure in runbook

### Long-term (TODO)

- [ ] Consider dedicated etcd nodes (not co-located with API servers)
- [ ] Evaluate adding more worker nodes
- [ ] Implement PodDisruptionBudget for critical workloads
- [ ] Add Flux webhook notifications for failures
- [ ] Consider implementing GitOps pause/circuit breaker

---

## Files Modified During Incident

| File | Change |
|------|--------|
| `kubernetes/dev/deployments/apps/monitoring/helm-release.yaml` | Anti-affinity: required → preferred |
| `kubernetes/dev/deployments/apps/monitoring/custom-alerts.yaml` | Added `release: kube-prometheus-stack` label |
| `kubernetes/dev/deployments/apps/wordpress/deployment.yaml` | Memory request: 128Mi → 200Mi |
| `disaster-recovery/issues/grafana-antiaffinity-rollout-stuck.md` | Created |
| `disaster-recovery/issues/prometheusrule-not-picked-up.md` | Created |
| `disaster-recovery/issues/hpa-memory-scaling-behavior.md` | Created |

---

## References

- [Kubernetes Pod Anti-Affinity](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#inter-pod-affinity-and-anti-affinity)
- [Flux HelmRelease Remediation](https://fluxcd.io/flux/components/helm/helmreleases/#configuring-failure-remediation)
- [HPA Resource Metrics](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#algorithm-details)
- [etcd Performance](https://etcd.io/docs/v3.5/op-guide/performance/)

---

## Appendix: Full Command History

```bash
# Discovery
kubectl get pods -n monitoring | grep grafana
kubectl describe pod kube-prometheus-stack-grafana-xxx -n monitoring

# Anti-affinity check
kubectl get deployment kube-prometheus-stack-grafana -n monitoring -o yaml | grep -A20 "affinity:"

# HelmRelease status
kubectl get helmrelease kube-prometheus-stack -n monitoring
kubectl describe helmrelease kube-prometheus-stack -n monitoring

# etcd health (failed during incident)
crictl exec $(crictl ps | grep etcd | awk '{print $1}') etcdctl endpoint status

# API server logs
crictl logs $(crictl ps | grep kube-apiserver | head -1 | awk '{print $1}') 2>&1 | tail -50

# Emergency suspension
flux suspend kustomization --all
flux suspend helmrelease --all -A

# Recovery
flux resume kustomization --all
flux suspend helmrelease kube-prometheus-stack -n monitoring
flux resume helmrelease kube-prometheus-stack -n monitoring

# Verification
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed
kubectl get helmrelease kube-prometheus-stack -n monitoring
```

---

## Signature

**Incident Commander:** (self-managed homelab)
**Date:** 2026-04-18
**Review Status:** Pending review
