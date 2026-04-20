# HPA Autoscaling Test
# Date: 2026-04-17
# Status: COMPLETE ✅

---

## Objective

Test Horizontal Pod Autoscaler (HPA) functionality for WordPress deployment.
Verify automatic scale-up and scale-down based on CPU utilization.

---

## Prerequisites Deployed

### 1. metrics-server (Required for HPA)

```yaml
# kubernetes/dev/deployments/infrastructure/metrics-server/helm-release.yaml
replicas: 2
priorityClassName: app-standard
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:  # Must be on different nodes
args:
  - --kubelet-insecure-tls  # Required for kubeadm self-signed certs
```

**Verification:**
```bash
[root@k8s-master1 ~]# kubectl top nodes
NAME                    CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
k8s-master1.lab.local   164m         8%       1491Mi          70%
k8s-master2.lab.local   155m         7%       1584Mi          75%
k8s-master3.lab.local   162m         8%       1745Mi          82%
k8s-worker1.lab.local   134m         6%       1939Mi          67%
k8s-worker2.lab.local   106m         5%       1851Mi          64%
k8s-worker3.lab.local   131m         6%       2045Mi          71%

[root@k8s-master1 ~]# kubectl top pods -n apps
NAME                         CPU(cores)   MEMORY(bytes)
wordpress-5f649b595f-jwcnk   1m           110Mi
wordpress-5f649b595f-tpzrj   1m           63Mi
```

### 2. WordPress HPA Configuration

```yaml
# kubernetes/dev/deployments/apps/wordpress/hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: wordpress-hpa
  namespace: apps
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: wordpress
  minReplicas: 2
  maxReplicas: 4
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80  # Higher than CPU - safety net only
```

**Why 80% for memory (vs 70% for CPU)?**
- Memory doesn't release quickly like CPU (apps hold allocations)
- Could cause unnecessary scaling for temporary spikes
- CPU is primary bottleneck for WordPress (request processing)
- Memory metric acts as safety net for memory leaks

### 3. WordPress Deployment (replicas removed)

```yaml
# kubernetes/dev/deployments/apps/wordpress/deployment.yaml
spec:
  # replicas managed by HPA (see hpa.yaml)
  selector:
    matchLabels:
      app: wordpress
```

**Key change:** Removed hardcoded `replicas: 3` to let HPA control replica count.

---

## Understanding HPA

### Q: What is HPA?
**A:** Horizontal Pod Autoscaler - a Kubernetes resource that automatically scales pod replicas based on metrics (CPU, memory, or custom).

### Q: Does it scale up AND down automatically?
**A:** Yes.
```
Traffic spike → CPU > 70% → HPA adds pods → 2 → 3 → 4
Traffic drops → CPU < 70% → HPA removes pods → 4 → 3 → 2
```

### Q: Does HPA conflict with Flux or ReplicaSet?
**A:** No, if configured correctly:
- Remove `replicas` from Deployment in Git
- HPA owns the replica count
- Flux ignores fields it doesn't manage
- ReplicaSet just maintains whatever count Deployment specifies

### Q: Does HPA need external components?
**A:** Yes - **metrics-server** is required.
- metrics-server: Real-time CPU/Memory for HPA and `kubectl top`
- Prometheus: Historical metrics, dashboards (you have this, different purpose)

### Q: How does HPA handle multiple metrics (CPU + Memory)?
**A:** HPA evaluates ALL metrics and uses the HIGHEST recommended replica count.
```
CPU suggests: 3 replicas (because CPU at 90%)
Memory suggests: 2 replicas (because memory at 50%)
HPA picks: 3 replicas (max of all recommendations)
```
This ensures both metrics are satisfied.

### Q: Can HPA have 2 replicas without conflict (like remediation)?
**A:** Yes - metrics-server is stateless and read-only. Both replicas just collect same metrics. No decision conflict like remediation (which could both try to reboot same VM).

---

## Test 1: CPU Stress Test (Partial)

### Method
Artificially push CPU usage using `yes > /dev/null` inside container.

### Execution
```bash
# Exec into WordPress container
kubectl exec -it -n apps wordpress-5f649b595f-jwcnk -c wordpress -- bash

# Run CPU stress (multiple processes)
yes > /dev/null &
yes > /dev/null &
yes > /dev/null &
yes > /dev/null &
yes > /dev/null &
yes > /dev/null &
```

### Evidence - CPU Spike
```bash
[root@k8s-master1 ~]# kubectl top pods -n apps
NAME                         CPU(cores)   MEMORY(bytes)
wordpress-5f649b595f-jwcnk   501m         121Mi
wordpress-5f649b595f-n4dnm   1m           176Mi
```

### Evidence - HPA Detection
```bash
[root@k8s-master1 ~]# kubectl get hpa -n apps -w
NAME            REFERENCE              TARGETS        MINPODS   MAXPODS   REPLICAS   AGE
wordpress-hpa   Deployment/wordpress   cpu: 72%/70%   2         4         2          9m19s
wordpress-hpa   Deployment/wordpress   cpu: 71%/70%   2         4         2          9m30s
wordpress-hpa   Deployment/wordpress   cpu: 72%/70%   2         4         2          9m45s
```

### Evidence - Container CPU Throttling
```
top - 13:00:18 up  4:20,  0 users,  load average: 0.11, 0.13, 0.15
%Cpu(s):  8.2 us, 20.3 sy,  0.0 ni, 70.3 id,  0.2 wa,  0.8 hi,  0.2 si,  0.0 st

    PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND
     89 root      20   0    2576   1504   1392 R  24.6   0.0   0:11.00 yes
     84 root      20   0    2576   1524   1416 R   5.3   0.1   0:33.81 yes
     87 root      20   0    2576   1432   1324 R   5.3   0.0   0:07.62 yes
     88 root      20   0    2576   1532   1424 R   5.3   0.1   0:08.80 yes
     85 root      20   0    2576   1468   1360 R   5.0   0.0   0:31.20 yes
     86 root      20   0    2576   1544   1436 R   5.0   0.1   0:17.25 yes
```

### Finding: HPA Did NOT Scale Up

**Why?**

1. **CPU Throttling:** Container has resource limits that cap CPU usage
   - 6 `yes` processes running but throttled
   - `70.3% idle` in `top` = container hitting its CPU limit
   - Cannot use more CPU than limits allow

2. **HPA Math:**
   ```
   Current: 72% / Target: 70% = 1.028 ratio
   Desired replicas = ceil(2 × 1.028) = ceil(2.057) = 3
   ```
   Should scale to 3, but margin is very small (2% over threshold).

3. **Only One Pod Stressed:**
   - Pod 1: 501m CPU (stressed)
   - Pod 2: 1m CPU (idle)
   - Average: ~250m → shows as 72% of requests

### Solution for Next Test

Stress BOTH pods to push average CPU higher:
```bash
# Stress pod 1
kubectl exec -it -n apps wordpress-5f649b595f-jwcnk -c wordpress -- sh -c 'yes > /dev/null & yes > /dev/null &'

# Stress pod 2
kubectl exec -it -n apps wordpress-5f649b595f-n4dnm -c wordpress -- sh -c 'yes > /dev/null & yes > /dev/null &'
```

Expected: Average CPU ~140% → HPA scales to 3 or 4 pods.

---

## Test 2: Stress Both Pods - SUCCESS ✅

### Method
Stress BOTH pods simultaneously to push average CPU above threshold.

### Execution
```bash
# Pod 1
kubectl exec -n apps wordpress-5f649b595f-jwcnk -c wordpress -- sh -c 'yes > /dev/null & yes > /dev/null & yes > /dev/null &'

# Pod 2
kubectl exec -n apps wordpress-5f649b595f-n4dnm -c wordpress -- sh -c 'yes > /dev/null & yes > /dev/null & yes > /dev/null &'
```

### Evidence - Scale UP
```bash
# Before stress
wordpress-hpa   Deployment/wordpress   cpu: 0%/70%   2         4         2

# During stress
wordpress-hpa   Deployment/wordpress   cpu: 95%/70%   2         4         4  ← SCALED!

# Pod listing after scale
NAME                         CPU(cores)   MEMORY(bytes)
wordpress-5f649b595f-c6rz8   1m           193Mi         ← NEW
wordpress-5f649b595f-jwcnk   500m         120Mi         ← stressed
wordpress-5f649b595f-n4dnm   500m         52Mi          ← stressed
wordpress-5f649b595f-pk265   1m           185Mi         ← NEW
```

**Result:** 2 → 4 pods in ~30 seconds

---

## Test 3: Scale Down - SUCCESS ✅

### Method
Kill stress on one pod, observe partial scale-down.

### Execution
```bash
kubectl exec -n apps wordpress-5f649b595f-jwcnk -c wordpress -- sh -c 'kill $(pgrep yes)'
```

### Evidence - Scale DOWN
```bash
# After killing stress on 1 pod
wordpress-hpa   Deployment/wordpress   cpu: 72%/70%   2         4         4
wordpress-hpa   Deployment/wordpress   cpu: 44%/70%   2         4         4
wordpress-hpa   Deployment/wordpress   cpu: 36%/70%   2         4         4   ← waiting...
wordpress-hpa   Deployment/wordpress   cpu: 36%/70%   2         4         4   ← still waiting
wordpress-hpa   Deployment/wordpress   cpu: 48%/70%   2         4         3   ← SCALED DOWN!

# HPA Events
Events:
  Normal  SuccessfulRescale  10m   horizontal-pod-autoscaler  New size: 4; reason: cpu above target
  Normal  SuccessfulRescale  30s   horizontal-pod-autoscaler  New size: 3; reason: All metrics below
```

**Result:** 4 → 3 pods after ~9 minutes (stabilization window)

### Why Not 3 → 2 (While Stress Running)?

With 1 pod still stressed:
```
Pod 1 (stressed): 500m / 100m request = 500%
Pod 2 (idle):     1m / 100m request   = 1%
Pod 3 (idle):     1m / 100m request   = 1%
Average: (500 + 1 + 1) / 3 = 167% → shows as ~48-50%
```

If HPA scaled to 2:
```
Pod 1 (stressed): 500m
Pod 2 (idle):     1m
Average: 501m / 2 = 250m per pod = 250%
```

HPA is smart - won't scale down if it would push utilization ABOVE threshold.

---

## Test 4: Complete Scale Down - SUCCESS ✅

### Method
Kill remaining stress process on last pod.

### Execution
```bash
kubectl exec -n apps wordpress-5f649b595f-n4dnm -c wordpress -- sh -c 'kill $(pgrep yes)'
```

### Evidence - Final Scale Down
```bash
wordpress-hpa   Deployment/wordpress   cpu: 0%/70%   2         4         3
wordpress-hpa   Deployment/wordpress   cpu: 0%/70%   2         4         2   ← SCALED!

# Final events
Events:
  Normal  SuccessfulRescale  28m   New size: 4; reason: cpu above target
  Normal  SuccessfulRescale  18m   New size: 3; reason: All metrics below
  Normal  SuccessfulRescale  27s   New size: 2; reason: All metrics below
```

**Result:** 3 → 2 pods after ~10 minutes (stabilization window)

---

## Test Summary - ALL PASSED ✅

| Test | Action | Result | Time |
|------|--------|--------|------|
| Scale UP | Stress 2 pods | 2 → 4 pods | ~30 seconds |
| Scale DOWN (partial) | Kill 1 stress | 4 → 3 pods | ~10 minutes |
| Scale DOWN (full) | Kill remaining stress | 3 → 2 pods | ~10 minutes |

**Full cycle verified:** `2 → 4 → 3 → 2`

### Final HPA Events
```bash
Events:
  Normal  SuccessfulRescale  28m   New size: 4; reason: cpu above target
  Normal  SuccessfulRescale  18m   New size: 3; reason: All metrics below
  Normal  SuccessfulRescale  27s   New size: 2; reason: All metrics below
```

### Key Timing Observations
- **Scale UP:** Fast (~30 seconds) - quick response to load
- **Scale DOWN:** Slow (~10 minutes) - conservative stabilization window
- **Reason:** Prevents thrashing (rapid up/down cycles)

---

## Optional Future Tests

### HTTP Load Test (Realistic)
- [ ] Use `hey` or `ab` to generate real traffic
- [ ] Verify HPA responds to actual web requests
- [ ] Compare to artificial CPU stress

---

## HPA Scaling Algorithm

```
desiredReplicas = ceil(currentReplicas × (currentMetricValue / desiredMetricValue))

Example:
- Current: 2 replicas
- Current CPU: 140%
- Target CPU: 70%
- Desired = ceil(2 × (140/70)) = ceil(4) = 4 replicas
```

**Stabilization Windows:**
- Scale up: ~15-30 seconds (fast response to load)
- Scale down: ~5 minutes (conservative to avoid thrashing)

---

## Related Configuration

### WordPress Resource Limits
```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m      # Max CPU per container
    memory: 512Mi
```

**Note:** HPA percentage is based on `requests`, not `limits`.
- If request = 100m and usage = 70m → 70%
- If request = 100m and usage = 140m → 140% (can exceed if limits allow)

---

## Files Modified

| File | Change |
|------|--------|
| `kubernetes/dev/deployments/apps/wordpress/deployment.yaml` | Removed `replicas: 3` |
| `kubernetes/dev/deployments/apps/wordpress/hpa.yaml` | New - HPA configuration (CPU + Memory) |
| `kubernetes/dev/deployments/apps/wordpress/kustomization.yaml` | Added `hpa.yaml` |
| `kubernetes/dev/deployments/infrastructure/metrics-server/` | New - metrics-server setup |

### HPA Update: Added Memory Metric
```yaml
# Added memory as secondary metric (safety net)
- type: Resource
  resource:
    name: memory
    target:
      type: Utilization
      averageUtilization: 80  # Higher threshold than CPU
```

---

## Commands Reference

```bash
# Watch HPA status
kubectl get hpa -n apps -w

# Watch pods
kubectl get pods -n apps -w

# Check CPU usage
kubectl top pods -n apps

# Stress container CPU
kubectl exec -it -n apps <pod> -c wordpress -- sh -c 'yes > /dev/null &'

# Kill stress
kubectl exec -it -n apps <pod> -c wordpress -- killall yes

# HTTP load test
hey -n 10000 -c 50 http://wordpress-dev.lab.local/
```

---

## Lessons Learned

1. **metrics-server required for HPA** - Without it, `kubectl top` and HPA don't work
2. **Remove hardcoded replicas** - Let HPA own the replica count
3. **CPU limits affect stress tests** - Container throttling limits how much CPU stress processes can use
4. **Stress all pods for accurate test** - Single pod stress may not push average high enough
5. **HPA has stabilization windows** - Won't react instantly to small changes
6. **Scale-down is conservative** - ~5-10 minutes vs ~30 seconds for scale-up
7. **HPA prevents bad scale-down** - Won't scale if doing so would exceed threshold
8. **Memory ≠ CPU patterns** - Stressed pod (55Mi) vs new pod (204Mi) - `yes` uses CPU not memory
9. **Mi = Mebibytes** - 512Mi ≈ 536MB (1024-based, approximately megabytes)
