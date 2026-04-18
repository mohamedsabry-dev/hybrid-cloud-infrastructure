# Issue: HPA Memory-Based Scaling Unexpected Behavior

**Status:** RESOLVED
**Date Discovered:** 2026-04-18
**Resolution:** Increased memory request from 128Mi to 200Mi

---

## Summary

WordPress HPA triggered `KubeHpaMaxedOut` alert with pods scaled to max (4) despite low apparent memory usage. Investigation revealed misunderstanding of how HPA calculates memory percentage and that the memory request (128Mi) was too close to actual idle usage (~72Mi), causing unnecessary scaling.

---

## Alert Received

```
alertname = KubeHpaMaxedOut
horizontalpodautoscaler = wordpress-hpa
namespace = apps
description = HPA apps/wordpress-hpa has been running at max replicas for longer than 15 minutes
```

---

## Initial Confusion

### Symptom 1: Low usage but maxed out replicas

```bash
[root@k8s-master1 ~]# kubectl top pods -n apps
NAME                         CPU(cores)   MEMORY(bytes)
wordpress-5f649b595f-7qpbx   2m           98Mi
wordpress-5f649b595f-jwcnk   1m           117Mi
wordpress-5f649b595f-mpgx8   2m           106Mi
wordpress-5f649b595f-twj77   1m           113Mi
```

**Question:** Why 4 pods when each only uses ~100Mi and limit is 512Mi?

### Symptom 2: HPA showing 64% but kubectl top shows higher

```bash
[root@k8s-master1 ~]# kubectl get hpa -n apps
NAME            REFERENCE              TARGETS                        MINPODS   MAXPODS   REPLICAS
wordpress-hpa   Deployment/wordpress   cpu: 0%/70%, memory: 64%/80%   2         4         4
```

**Question:** How is 100Mi = 64% of 512Mi limit? That math doesn't work.

---

## Root Cause Discovery

### Key Insight #1: HPA uses REQUEST, not LIMIT

**This was the fundamental misunderstanding.**

```yaml
resources:
  requests:
    memory: "128Mi"   ← HPA uses THIS as 100%
  limits:
    memory: "512Mi"   ← HPA ignores this (just a ceiling)
```

**HPA Formula:**
```
percentage = actual_usage / REQUEST (not limit!)
desiredReplicas = ceil(currentReplicas × currentMetric / targetMetric)
```

### Key Insight #2: HPA only measures containers with requests

Pod has multiple containers:
- `wordpress` - has 128Mi request → HPA tracks this
- `vault-agent` - injected sidecar → separate/no request

```bash
[root@k8s-master1 ~]# kubectl top pods -n apps --containers
POD                          NAME          CPU(cores)   MEMORY(bytes)
wordpress-5f649b595f-7qpbx   vault-agent   1m           27Mi
wordpress-5f649b595f-7qpbx   wordpress     1m           76Mi
wordpress-5f649b595f-jwcnk   vault-agent   1m           32Mi
wordpress-5f649b595f-jwcnk   wordpress     1m           84Mi
```

**Total pod memory:** ~110Mi (wordpress 76Mi + vault-agent 32Mi)
**HPA sees only:** wordpress container = 76Mi
**HPA calculation:** 76Mi / 128Mi = 59% ✓ (close to reported 64%)

### Key Insight #3: Memory is NOT constant

Initially thought WordPress idle = constant ~72Mi. Then discovered:

```bash
# During video playback on WordPress site:
POD                          NAME          MEMORY(bytes)
wordpress-5f649b595f-7qpbx   wordpress     186Mi        ← SPIKE!
wordpress-5f649b595f-jwcnk   wordpress     90Mi
```

**Memory behavior:**
| State | WordPress memory |
|-------|------------------|
| Idle | 70-90Mi |
| Video/media load | 150-200Mi spike |
| After activity | drops back to 70-90Mi |

---

## The Scaling Timeline Reconstructed

### Phase 1: Initial state (2 pods)
```
2 pods × 72Mi = 144Mi usage
2 pods × 128Mi = 256Mi request
HPA: 144/256 = 56% → stable at minReplicas (2)
```

### Phase 2: Video opened (~30 min ago)
```
1 pod spikes to 186Mi, other at 72Mi
Average: (186 + 72) / 2 = 129Mi per pod
HPA: 129Mi / 128Mi = 100%+ → SCALE UP!
```

### Phase 3: Scaled to 3, still high
```
Load + new pod startup memory
HPA still above 80% → SCALE UP to 4
```

### Phase 4: Video closed, 4 pods running
```
4 pods × 72Mi = 288Mi usage
4 pods × 128Mi = 512Mi request
HPA: 288/512 = 56%
desiredReplicas = ceil(4 × 56/80) = ceil(2.8) = 3

Eventually scaled down to 3
```

### Phase 5: Stable at 3 pods
```
3 pods × 72Mi = 216Mi usage
3 pods × 128Mi = 384Mi request
HPA: 216/384 = 56%
desiredReplicas = ceil(3 × 56/80) = ceil(2.1) = 3 ✓
```

---

## Why 128Mi Request Was Wrong

| Metric | Value | Problem |
|--------|-------|---------|
| WordPress idle | 70-90Mi | Very close to 128Mi request |
| WordPress active | 150-200Mi | Exceeds 128Mi request |
| HPA target | 80% of request = 102Mi | Below active usage |

**Result:** Any user activity (video, image gallery) causes immediate scaling.

---

## Solution: Increase Memory Request to 200Mi

### Why 200Mi?

| Request | Idle % | Active % | Behavior |
|---------|--------|----------|----------|
| 128Mi (old) | 56-70% | 116-156% | Scales on any activity |
| 200Mi (new) | 35-45% | 75-93% | Scales only on heavy load |
| 256Mi | 27-35% | 59-73% | Rarely scales (but wastes reservation) |

**200Mi chosen because:**
1. Worker nodes have limited memory (~3.25GB total)
2. Higher request = more reserved per pod = fewer pods fit
3. 200Mi balances stability vs resource efficiency

### New expected behavior

```
2 pods idle:
  2 × 72Mi / (2 × 200Mi) = 144/400 = 36% → stable

1 pod video spike to 186Mi:
  (186 + 72) / (2 × 200Mi) = 258/400 = 64% → stable (below 80%)

Only scales if multiple pods hit high usage simultaneously
```

---

## Related Concepts Clarified

### REQUEST vs LIMIT

| Concept | REQUEST | LIMIT |
|---------|---------|-------|
| Purpose | Guaranteed/reserved | Maximum allowed |
| Scheduler | Uses to place pods | Ignores |
| HPA | Calculates % against this | Ignores |
| OOM Kill | No | Yes, if exceeded |

### Why Kubernetes designed it this way

- **REQUEST** = "what I normally need" (baseline capacity)
- **LIMIT** = "max burst allowed" (safety ceiling)
- **HPA philosophy:** Scale when you're using more than your "normal" capacity

If HPA used LIMIT:
- Would need 70% of 512Mi = 358Mi before scaling
- Pod would be severely overloaded before help arrives
- Against the principle of proactive scaling

---

## Verification Commands

```bash
# Check per-container memory (not whole pod)
kubectl top pods -n apps --containers

# Check HPA status and events
kubectl describe hpa wordpress-hpa -n apps

# Watch HPA in real-time
watch -n2 'kubectl get hpa -n apps'

# Check what HPA is actually measuring
kubectl get hpa wordpress-hpa -n apps -o yaml | grep -A20 status
```

---

## Files Modified

| File | Change |
|------|--------|
| `kubernetes/dev/deployments/apps/wordpress/deployment.yaml` | Memory request 128Mi → 200Mi |

---

## Lessons Learned

1. **HPA uses REQUEST, not LIMIT** - This is the most common HPA misunderstanding
2. **Check per-container usage** with `--containers` flag when pods have sidecars
3. **Memory is variable** - Don't assume steady-state usage, test with real workloads
4. **Request should have headroom** - At least 30-40% below request for idle state
5. **Watch actual spikes** - One user activity can trigger scaling cascade

---

## Test Procedure for Validation

After applying 200Mi request:

1. Apply change and wait for rollout:
   ```bash
   kubectl apply -f kubernetes/dev/deployments/apps/wordpress/deployment.yaml
   kubectl rollout status deployment wordpress -n apps
   ```

2. Verify HPA baseline:
   ```bash
   kubectl get hpa -n apps
   # Should show ~35-40% memory with 2 pods
   ```

3. Simulate load (open video/gallery on WordPress):
   ```bash
   watch -n2 'kubectl top pods -n apps --containers'
   # Should see spike but stay below 80%
   ```

4. Verify no unnecessary scaling:
   ```bash
   kubectl describe hpa wordpress-hpa -n apps | grep -A5 Events
   # Should not show scaling events from normal usage
   ```
