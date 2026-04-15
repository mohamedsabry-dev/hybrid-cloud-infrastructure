# TS-K8S-031 | 2026-04-15 | RESOLVED (No Action Required)

## 1. Context
- System: Kubernetes Scheduler / Pod Anti-Affinity
- Environment: DEV (lab.local)
- Related components: WordPress deployment, HelmRelease, worker nodes
- Discovery: **Discovered during IPA Domain Down DR Test (Part 2)**

---

## 2. Issue

WordPress pods (3 replicas) scheduled unevenly despite anti-affinity configuration:
- 2 pods on k8s-worker3
- 1 pod on k8s-worker1
- 0 pods on k8s-worker2

Expected: 1 pod per worker node (even distribution).

---

## 3. Evidence

### Pod Distribution
```
apps  wordpress-56bf4b697d-87tvx  k8s-worker3.lab.local
apps  wordpress-56bf4b697d-8k8jc  k8s-worker3.lab.local
apps  wordpress-56bf4b697d-vxc69  k8s-worker1.lab.local
```

### Scheduling Timeline
```
6m25s: Pod 87tvx → worker3 (first)
6m13s: Pod 8k8jc → worker3 (second - same node)
6m3s:  Pod vxc69 → worker1 (third)
```

### Node Resource Allocation (At Scheduling Time)
| Node | CPU Requests | Memory Requests | Load Level |
|------|--------------|-----------------|------------|
| k8s-worker1 | 1280m (64%) | 898Mi (31%) | Moderate |
| k8s-worker2 | 1380m (69%) | 788Mi (27%) | Highest CPU |
| k8s-worker3 | 1230m (61%) | 508Mi (17%) | **Lowest** |

### Anti-Affinity Configuration
```yaml
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:   # <-- SOFT (preferred)
  - podAffinityTerm:
      labelSelector:
        matchLabels:
          app: wordpress
      topologyKey: kubernetes.io/hostname
    weight: 100
```

---

## 4. Root Cause Analysis

### Why Scheduler Chose worker3 Twice

1. **Soft Anti-Affinity** - `preferredDuringScheduling` means scheduler CAN ignore it
2. **Resource Scoring** - worker3 had lowest utilization (61% CPU, 17% memory)
3. **Score Calculation:**
   - worker3 gets HIGH score for resource availability
   - Anti-affinity subtracts penalty (weight 100)
   - Net score still higher than worker1/worker2
4. **Third Pod** - After 2 pods on worker3, anti-affinity penalty doubled, worker1 won

### Why Not worker2?
- worker2 had highest CPU utilization (69%)
- Scheduler preferred lower-utilized nodes

---

## 5. Options Considered

### Option A: Hard Anti-Affinity (Rejected)
```yaml
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:  # HARD requirement
  - labelSelector:
      matchLabels:
        app: wordpress
    topologyKey: kubernetes.io/hostname
```
**Risk:** If only 2 workers available, 3rd pod stays Pending forever.

### Option B: Topology Spread Constraints (Not Selected)
```yaml
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: kubernetes.io/hostname
  whenUnsatisfiable: DoNotSchedule
  labelSelector:
    matchLabels:
      app: wordpress
```
**Better for:** Controlled skew with fallback behavior.

### Option C: Keep Current Config (Selected)
- Scheduler makes intelligent resource-based decisions
- Anti-affinity is a preference, not a hard rule
- Current behavior is acceptable for HA (pods on 2 different nodes)

---

## 6. Decision

**Keep current configuration.**

### Reasoning:
1. WordPress has 2/3 pods on separate nodes - still HA
2. Scheduler optimized for resource utilization
3. Hard anti-affinity risks pending pods
4. Soft anti-affinity provides flexibility
5. If worker3 fails, pods reschedule to other nodes

### Acceptance Criteria Met:
- [x] No single point of failure (pods on multiple nodes)
- [x] Resource-efficient scheduling
- [x] No manual intervention required

---

## 7. Future Improvements (Optional)

If even distribution becomes critical:
1. Use `topologySpreadConstraints` with `maxSkew: 1`
2. Or balance worker node resources to reduce scoring differences
3. Or use Pod Topology Spread with `DoNotSchedule`

---

## 8. Related Files
- WordPress HelmRelease: `k8s/apps/wordpress/`
- DR Test: `disaster-recovery/tmp-ipa-domain-down-part2.md`
