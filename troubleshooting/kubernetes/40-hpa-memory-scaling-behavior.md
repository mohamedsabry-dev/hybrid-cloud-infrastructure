# TS-K8S-040 | 2026-04-18 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / HPA / WordPress
Sub-techs: HorizontalPodAutoscaler, memory-based scaling, resource requests vs
           limits, per-container metrics, Vault Agent sidecar
Environment: DEV k8s cluster | WordPress deployment with HPA
Discovered during: KubeHpaMaxedOut alert investigation
Related: TS-K8S-042 (discovered during same session)
Re-opened: No

_____________________________________________________________________

[Issue Description]
WordPress HPA triggered `KubeHpaMaxedOut` alert with pods scaled to max (4)
despite seemingly low memory usage. Investigation revealed I misunderstood how
HPA calculates memory percentage.

```
alertname = KubeHpaMaxedOut
horizontalpodautoscaler = wordpress-hpa
namespace = apps
description = HPA apps/wordpress-hpa has been running at max replicas for longer than 15 minutes
```

_____________________________________________________________________

[Analysis]

# Step 1: Initial confusion — low usage but maxed replicas

```
kubectl top pods -n apps
NAME                         CPU(cores)   MEMORY(bytes)
wordpress-5f649b595f-7qpbx   2m           98Mi
wordpress-5f649b595f-jwcnk   1m           117Mi
wordpress-5f649b595f-mpgx8   2m           106Mi
wordpress-5f649b595f-twj77   1m           113Mi
```

4 pods at ~100Mi each. Limit is 512Mi. Why would HPA scale to max?

```
kubectl get hpa -n apps
NAME            REFERENCE              TARGETS                        MINPODS   MAXPODS   REPLICAS
wordpress-hpa   Deployment/wordpress   cpu: 0%/70%, memory: 64%/80%   2         4         4
```

How is 100Mi = 64% of 512Mi? That math doesn't work.

# Step 2: Key insight — HPA uses REQUEST, not LIMIT

This was the fundamental misunderstanding.

```yaml
resources:
  requests:
    memory: "128Mi"   ← HPA uses THIS as 100%
  limits:
    memory: "512Mi"   ← HPA ignores this
```

HPA formula: `percentage = actual_usage / REQUEST`

# Step 3: Per-container metrics — vault-agent sidecar skews total

```
kubectl top pods -n apps --containers
POD                          NAME          CPU(cores)   MEMORY(bytes)
wordpress-5f649b595f-7qpbx   vault-agent   1m           27Mi
wordpress-5f649b595f-7qpbx   wordpress     1m           76Mi
wordpress-5f649b595f-jwcnk   vault-agent   1m           32Mi
wordpress-5f649b595f-jwcnk   wordpress     1m           84Mi
```

Total pod memory: ~110Mi (wordpress 76Mi + vault-agent 32Mi). But HPA only sees
the wordpress container (the one with the request): 76Mi / 128Mi = 59%. Close to
the reported 64%.

# Step 4: Memory is NOT constant — spikes cause scaling

```
# During video playback on WordPress site:
wordpress-5f649b595f-7qpbx   wordpress     186Mi   ← SPIKE!
wordpress-5f649b595f-jwcnk   wordpress     90Mi
```

WordPress memory: idle 70-90Mi, video/media load 150-200Mi spike, drops back
after activity.

# Step 5: Reconstructed the scaling timeline

Phase 1 — initial (2 pods idle):
```
2 × 72Mi / (2 × 128Mi) = 144/256 = 56% → stable at minReplicas
```

Phase 2 — video opened:
```
(186 + 72) / (2 × 128Mi) = 258/256 = 100%+ → SCALE UP!
```

Phase 3 — scaled to 3, still high → SCALE UP to 4.

Phase 4 — video closed, 4 pods running:
```
4 × 72Mi / (4 × 128Mi) = 288/512 = 56% → eventually scaled down to 3
```

The problem: 128Mi request was too close to actual idle usage (~72Mi). Any user
activity (video, image gallery) immediately triggered scaling.

_____________________________________________________________________

[Final Root Cause]
Memory request (128Mi) was too close to actual WordPress idle usage (70-90Mi).
HPA calculates percentage against REQUEST (not LIMIT). Any normal user activity
(video playback, media load) spiked memory above the 80% target threshold,
triggering unnecessary scaling.

_____________________________________________________________________

[Final Solution]

Increased memory request from 128Mi to 200Mi:

```yaml
resources:
  requests:
    memory: "200Mi"   # Was 128Mi
  limits:
    memory: "512Mi"
```

Why 200Mi:
- Idle: 72Mi / 200Mi = 36% (plenty of headroom below 80% target)
- Video spike: 186Mi / 200Mi = 93% (scales only on heavy load)
- Worker nodes have limited memory (~3.25GB) — higher request wastes reservation
- 200Mi balances stability vs resource efficiency

Expected behavior with 200Mi:
```
2 pods idle: 2 × 72Mi / (2 × 200Mi) = 36% → stable
1 pod video spike: (186 + 72) / (2 × 200Mi) = 64% → stable (below 80%)
Only scales if multiple pods hit high usage simultaneously
```

File modified: `kubernetes/dev/deployments/apps/wordpress/deployment.yaml`

Verified: Yes — HPA stable at 2 replicas during normal usage, scales only on
genuine load.

_____________________________________________________________________

[Risk Level] LOW

Higher memory request reserves more per pod, but 200Mi is well within worker
node capacity.

_____________________________________________________________________

[References]
- TS-K8S-042 — Flux retry storm (discovered during same session)
