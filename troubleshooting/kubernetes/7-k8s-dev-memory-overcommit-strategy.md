# Case 7: K8s Dev Cluster Memory Over-Commitment — Dev/Prod Strategy

## Status: RESOLVED (Strategy Defined)
## Date: 2026-04-03
## Severity: Medium
## Environment: k8s-dev cluster
## Related Cases: [Case 8: Kubernetes Scheduler Limitations and Advanced Scheduling](./8-k8s-scheduler-limitations-and-advanced-scheduling.md)

---

## 1. Executive Summary

During NGINX Ingress Controller deployment on the dev cluster, we discovered memory over-commitment on worker nodes. Dev cluster has limited RAM (2.5GB per worker), making it unsuitable for running all applications simultaneously.

**Strategy Adopted:**
- Dev cluster: Test one application at a time, then promote to prod and delete from dev
- Prod cluster: Run all apps simultaneously (adequate RAM available)

**Additional Discovery:**
During investigation, we uncovered fundamental Kubernetes scheduler limitations regarding memory scheduling. This led to implementing advanced scheduling solutions (VPA + Descheduler). See [Case 8](./8-k8s-scheduler-limitations-and-advanced-scheduling.md) for details.

---

## 2. Issue Discovery

### 2.1 Initial Symptom

After deploying NGINX Ingress Controller (3 replicas), memory analysis showed severe over-commitment on worker1.

### 2.2 Investigation Commands and Output

**Command: Check node memory allocation**
```bash
kubectl describe nodes | grep -E "(Name:|memory)"
```

**Output:**
```
Name:               k8s-master1.lab.local
  memory:             1772304Ki
  memory:             1569904Ki
  memory             160Mi (10%)  500Mi (32%)
Name:               k8s-master2.lab.local
  memory:             1772304Ki
  memory:             1569904Ki
  memory             160Mi (10%)  500Mi (32%)
Name:               k8s-master3.lab.local
  memory:             1772304Ki
  memory:             1569904Ki
  memory             160Mi (10%)  500Mi (32%)
Name:               k8s-worker1.lab.local
  memory:             2517080Ki
  memory:             2414680Ki
  memory             406Mi (17%)  4596Mi (194%)   ← CRITICAL: 194% over-committed
Name:               k8s-worker2.lab.local
  memory:             2517080Ki
  memory:             2414680Ki
  memory             220Mi (9%)   670Mi (28%)
Name:               k8s-worker3.lab.local
  memory:             2517080Ki
  memory:             2414680Ki
  memory             320Mi (13%)  1970Mi (83%)
```

**Analysis:**

| Node | Total RAM | Allocatable | Requests | Limits | Status |
|------|-----------|-------------|----------|--------|--------|
| k8s-master1 | 1.7GB | 1.6GB | 160Mi (9%) | 500Mi (31%) | ✅ OK |
| k8s-master2 | 1.7GB | 1.6GB | 160Mi (9%) | 500Mi (31%) | ✅ OK |
| k8s-master3 | 1.7GB | 1.6GB | 160Mi (9%) | 500Mi (31%) | ✅ OK |
| **k8s-worker1** | 2.5GB | 2.4GB | 406Mi (17%) | **4596Mi (194%)** | ⚠️ CRITICAL |
| k8s-worker2 | 2.5GB | 2.4GB | 220Mi (9%) | 670Mi (28%) | ✅ OK |
| k8s-worker3 | 2.5GB | 2.4GB | 320Mi (13%) | 1970Mi (83%) | ⚠️ Warning |

### 2.3 Root Cause Analysis

**Command: Check pods on worker1**
```bash
kubectl get pods -A -o wide --field-selector spec.nodeName=k8s-worker1.lab.local
```

**Output:**
```
NAMESPACE     NAME                                      READY   STATUS    NODE
flux-system   helm-controller-xxx                       1/1     Running   k8s-worker1.lab.local
flux-system   kustomize-controller-xxx                  1/1     Running   k8s-worker1.lab.local
flux-system   notification-controller-xxx               1/1     Running   k8s-worker1.lab.local
flux-system   source-controller-xxx                     1/1     Running   k8s-worker1.lab.local
kube-system   calico-node-xxx                           1/1     Running   k8s-worker1.lab.local
kube-system   csi-nfs-node-xxx                          3/3     Running   k8s-worker1.lab.local
kube-system   kube-proxy-xxx                            1/1     Running   k8s-worker1.lab.local
```

**Root Cause Identified:**
- All 4 Flux controllers landed on worker1 by random scheduling
- Each Flux controller has ~1GB memory limit by default
- 4 controllers × ~1GB = ~4GB limits on a 2.4GB allocatable node = 194% over-commitment

**Command: Verify Flux controller resource limits**
```bash
kubectl describe deployment helm-controller -n flux-system | grep -A 10 "Limits"
```

**Output:**
```
    Limits:
      memory:  1Gi
    Requests:
      cpu:        100m
      memory:     64Mi
```

---

## 3. Concepts Clarified

### 3.1 Requests vs Limits

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     KUBERNETES MEMORY MODEL                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  REQUESTS (what scheduler uses):                                        │
│  ════════════════════════════════                                       │
│  • Guaranteed memory for the pod                                        │
│  • Scheduler uses this to place pods                                    │
│  • Sum of requests ≤ Node allocatable = OK                              │
│                                                                         │
│  LIMITS (maximum allowed):                                              │
│  ═════════════════════════                                              │
│  • Maximum memory pod CAN use                                           │
│  • Can be > 100% of node (over-commitment allowed)                      │
│  • If pod exceeds limit → OOM killed                                    │
│  • If node runs out of actual memory → OOM killer picks victims         │
│                                                                         │
│  EXAMPLE:                                                               │
│  ─────────                                                              │
│  Node has 2GB allocatable                                               │
│  Pod A: requests=100Mi, limits=1Gi                                      │
│  Pod B: requests=100Mi, limits=1Gi                                      │
│  Pod C: requests=100Mi, limits=1Gi                                      │
│                                                                         │
│  Total requests: 300Mi (15%) ← Scheduler sees this, says "OK"           │
│  Total limits: 3Gi (150%) ← Over-committed, but allowed                 │
│                                                                         │
│  Risk: If all 3 pods try to use 1Gi simultaneously → OOM                │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

| Metric | Meaning | Scheduler Uses? | Risk When High |
|--------|---------|-----------------|----------------|
| **Requests** | Guaranteed allocation | ✅ Yes | Low requests = pods may starve |
| **Limits** | Maximum allowed | ❌ No | Over 100% = OOM risk under load |

### 3.2 Why 194% Over-Commitment is Risky

**Current State:**
```
Worker1 Memory Budget:
├── Allocatable: 2414Mi (2.4GB)
├── Requests: 406Mi (17%) ← Actual guaranteed
├── Limits: 4596Mi (194%) ← Maximum if all pods burst
└── Gap: 4190Mi that pods COULD request but node CANNOT provide
```

**Scenarios:**

| Scenario | What Happens |
|----------|--------------|
| Normal operation | Pods use ~requests, no problem |
| One pod spikes | Pod gets extra memory up to limit, others unaffected |
| All pods spike | Node runs out of memory → OOM killer → random pod deaths |
| Memory leak | Pod keeps growing → hits limit → OOM killed |

### 3.3 Why It's Acceptable for Dev (For Now)

1. **Actual usage is low** - requests only at 17%
2. **Light workloads** - no production traffic
3. **Monitoring in place** - we watch for issues
4. **Temporary** - strategy to manage this going forward

---

## 4. Strategy Adopted

### 4.1 Dev Cluster Strategy (Limited RAM)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        DEV CLUSTER WORKFLOW                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ALWAYS RUNNING (Infrastructure):         TEST ONE AT A TIME (Apps):   │
│  ══════════════════════════════════        ═══════════════════════════  │
│                                                                         │
│  • Flux controllers (~256Mi actual)        1. Deploy WordPress          │
│  • Ingress Controller (3 replicas)            ↓ Test functionality      │
│  • Vault Agent Injector                       ↓ Verify Ingress          │
│  • Calico CNI (per node)                      ↓ Check logs              │
│  • CoreDNS                                 2. Promote to Prod           │
│  • CSI NFS driver                             (copy manifests)          │
│                                            3. Delete from Dev           │
│  Estimated: ~1.5GB limits                     (remove from kustomization)
│  Leaves: ~1GB for testing                  4. Deploy Prometheus         │
│                                               ↓ Test metrics            │
│                                            5. Promote to Prod           │
│                                            6. Delete from Dev           │
│                                               ... repeat ...            │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Why This Works:**
- Dev only needs one app at a time for testing
- Once tested, app moves to prod where RAM is adequate
- Dev stays lean, prod runs everything

---

## 5. Files Modified

### 5.1 Kubernetes Changes (Anti-Affinity)

See [Case 8](./8-k8s-scheduler-limitations-and-advanced-scheduling.md) for pod distribution fixes.

| File | Change | Purpose |
|------|--------|---------|
| `kubernetes/dev/flux/flux-system/flux-pod-anti-affinity.yaml` | Created | Spread Flux pods |
| `kubernetes/prod/flux/flux-system/flux-pod-anti-affinity.yaml` | Created | Spread Flux pods |
| `kubernetes/dev/deployments/infrastructure/ingress/helm-release.yaml` | Added affinity | Spread Ingress pods |
| `kubernetes/prod/deployments/infrastructure/ingress/helm-release.yaml` | Added affinity | Spread Ingress pods |

---

## 6. Monitoring Commands Reference

### 6.1 Node Memory Status

```bash
# Quick overview - requests and limits per node
kubectl describe nodes | grep -E "(Name:|memory)"

# Detailed breakdown per node
kubectl describe node k8s-worker1.lab.local | grep -A 10 "Allocated resources"
```

**Sample Output:**
```
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests     Limits
  --------           --------     ------
  cpu                680m (34%)   2 (100%)
  memory             348Mi (14%)  2718Mi (115%)
```

### 6.2 Pods Per Node

```bash
# All pods on a specific node
kubectl get pods -A -o wide --field-selector spec.nodeName=k8s-worker1.lab.local

# Count pods per node
kubectl get pods -A -o wide --no-headers | awk '{print $8}' | sort | uniq -c

# Loop through all workers
for node in k8s-worker1 k8s-worker2 k8s-worker3; do
  echo "=== $node ==="
  kubectl get pods -A --field-selector spec.nodeName=$node.lab.local --no-headers | wc -l
  echo "pods"
done
```

### 6.3 Resource Usage (Requires metrics-server)

```bash
# If metrics-server is installed
kubectl top nodes
kubectl top pods -A --sort-by=memory
```

### 6.4 Check for Memory Pressure

```bash
# Check node conditions
kubectl describe nodes | grep -E "(Name:|MemoryPressure)"

# Check for OOM events
kubectl get events -A --sort-by='.lastTimestamp' | grep -i oom
```

---

## 7. Lessons Learned

1. **Limits ≠ Usage**: High limits don't mean high actual usage. Requests show real consumption.

2. **Over-commitment is allowed**: Kubernetes allows limits > node capacity by design. It's a feature, not a bug.

3. **Plan for growth**: Size prod cluster for all planned workloads upfront.

4. **Dev can be small**: Dev only needs to run one app at a time for testing.

5. **Monitor early**: Check memory before deploying new applications.

6. **Spread critical pods**: Use anti-affinity for controllers. See [Case 8](./8-k8s-scheduler-limitations-and-advanced-scheduling.md).

7. **GitOps for everything**: Even infrastructure config changes should go through Git.

---

## 8. Open Questions Addressed in Case 8

During this investigation, we discovered deeper scheduler limitations:

1. **Why did all Flux pods land on one node?** → Scheduler doesn't rebalance; anti-affinity needed
2. **Why didn't anti-affinity work on first deploy?** → Rolling update saw OLD pods on worker1
3. **Why doesn't scheduler consider limits?** → By design, uses only requests
4. **Can we make scheduling smarter?** → Yes, with VPA + Descheduler

These questions are fully addressed in [Case 8: Kubernetes Scheduler Limitations and Advanced Scheduling](./8-k8s-scheduler-limitations-and-advanced-scheduling.md).

---

## 9. Resolution Summary

| Item | Dev Cluster | Prod Cluster |
|------|-------------|--------------|
| Worker RAM | 2.5GB (unchanged) | Adequate |
| Strategy | Test one app at a time | Run all apps |
| Anti-affinity | ✅ Implemented | ✅ Implemented |
| Advanced scheduling | 🔄 Planned (VPA + Descheduler) | 🔄 Planned |

**Status: RESOLVED** - Strategy defined and initial mitigations in place. Advanced scheduling to be implemented as part of Case 8.
