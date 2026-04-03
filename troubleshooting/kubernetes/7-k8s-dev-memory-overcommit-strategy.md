# Case 7: K8s Dev Cluster Memory Over-Commitment — Dev/Prod Strategy

## Status: RESOLVED (Strategy Defined)
## Date: 2026-04-03
## Severity: Medium
## Environment: k8s-dev cluster
## Related: Ingress Controller deployment, Flux controllers

---

## 1. Executive Summary

During NGINX Ingress Controller deployment on the dev cluster, we discovered memory over-commitment on worker nodes. Dev cluster has limited RAM (2.5GB per worker), making it unsuitable for running all applications simultaneously.

**Strategy Adopted:**
- Dev cluster: Test one application at a time, then promote to prod and delete from dev
- Prod cluster: Increase worker memory from 8GB to 10GB to run all apps simultaneously

---

## 2. Issue Discovery

### Symptom

After deploying NGINX Ingress Controller (3 replicas), memory analysis showed:

```bash
kubectl describe nodes | grep -E "(Name:|memory)"
```

**Results:**

| Node | Total RAM | Allocatable | Requests | Limits |
|------|-----------|-------------|----------|--------|
| k8s-master1 | 1.7GB | 1.6GB | 160Mi (9%) | 500Mi (31%) |
| k8s-master2 | 1.7GB | 1.6GB | 160Mi (9%) | 500Mi (31%) |
| k8s-master3 | 1.7GB | 1.6GB | 160Mi (9%) | 500Mi (31%) |
| **k8s-worker1** | 2.5GB | 2.4GB | 406Mi (17%) | **4596Mi (194%)** ⚠️ |
| k8s-worker2 | 2.5GB | 2.4GB | 220Mi (9%) | 670Mi (28%) |
| k8s-worker3 | 2.5GB | 2.4GB | 320Mi (13%) | 1970Mi (83%) |

### Root Cause

**Worker1** hosts all 4 Flux controllers (helm-controller, kustomize-controller, notification-controller, source-controller), each with ~1GB memory limits by default.

```
4 Flux controllers × ~1GB limits = ~4GB limits on a 2.4GB node
```

---

## 3. Concepts Clarified

### Requests vs Limits

| Metric | Meaning | Risk |
|--------|---------|------|
| **Requests** | What pods are actually using | Low = OK |
| **Limits** | Maximum pods CAN use | Over 100% = OOM risk under load |

### Why It's OK for Now

- Actual usage (requests) is low (~17% on worker1)
- Limits only matter if pods actually try to use that memory
- Dev cluster has light workloads

### Why It's a Problem for Future

Planned applications need significant memory:

| Application | Estimated Memory |
|-------------|-----------------|
| WordPress + MariaDB | 500MB - 1GB |
| Prometheus | 500MB - 1GB |
| Grafana | 200MB - 500MB |
| Loki | 500MB - 1GB |
| **Total** | ~3-4GB |

With only 2.4GB allocatable per worker, cannot run all simultaneously on dev.

---

## 4. Strategy Adopted

### Dev Cluster (Limited RAM)

```
┌─────────────────────────────────────────────────────────────┐
│                    DEV WORKFLOW                             │
│                                                             │
│   Always Running:              Test ONE at a time:          │
│   • Flux controllers           1. Deploy WordPress          │
│   • Ingress Controller            ↓ test OK                 │
│   • Vault Injector             2. Promote to prod           │
│   • System pods                3. Delete from dev           │
│                                4. Deploy Prometheus         │
│                                   ↓ test OK                 │
│                                5. Promote to prod           │
│                                6. Delete from dev           │
│                                ... repeat ...               │
└─────────────────────────────────────────────────────────────┘
```

### Prod Cluster (Adequate RAM)

**Action:** Increase worker memory from 8GB to 10GB in Terraform.

```hcl
# terraform/prod/proxmox/vms/k8s_workers/variables.tf
# Change: memory = 8192  → memory = 10240
```

This provides ~9.5GB allocatable per worker, enough to run:
- Flux + Ingress + Vault + System (~1.5GB)
- All applications (~4GB)
- Headroom for spikes (~4GB)

---

## 5. Files Modified

| File | Change |
|------|--------|
| `terraform/prod/proxmox/vms/k8s_workers/variables.tf` | memory: 8192 → 10240 (all 3 workers) |

---

## 6. Commands for Monitoring

```bash
# Check node memory (without metrics-server)
kubectl describe nodes | grep -E "(Name:|memory)"

# Check pods per node
kubectl get pods -A -o wide --field-selector spec.nodeName=<node-name>

# Check specific pod resources
kubectl describe pod <pod-name> -n <namespace> | grep -A 5 "Limits"

# With metrics-server (if installed)
kubectl top nodes
kubectl top pods -A
```

---

## 7. Future Considerations

1. **Install metrics-server** for real-time memory monitoring
2. **Consider pod anti-affinity** to spread Flux controllers across nodes
3. **Reduce Flux controller limits** if memory pressure occurs
4. **Add more workers** if workload grows beyond prod capacity

---

## 8. Flux Pod Distribution Fix

### Problem
All 4 Flux controllers landed on worker1 by chance during initial scheduling, creating a single point of failure.

### Root Cause
- Scheduler uses **requests** (low) for decisions, ignores **limits** (high)
- No pod anti-affinity configured by default
- Scheduler doesn't rebalance existing pods

### Solution: GitOps Kustomize Patch

Added anti-affinity patch to Flux's own configuration in Git. Flux manages itself and applies the patch automatically.

**Files Created:**
```
kubernetes/dev/flux/flux-system/flux-pod-anti-affinity.yaml
kubernetes/prod/flux/flux-system/flux-pod-anti-affinity.yaml
```

**Files Modified:**
```
kubernetes/dev/flux/flux-system/kustomization.yaml
kubernetes/prod/flux/flux-system/kustomization.yaml
```

**Patch Content:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: helm-controller  # (repeated for all 4 controllers)
  namespace: flux-system
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app.kubernetes.io/part-of: flux
              topologyKey: kubernetes.io/hostname
```

**Kustomization Update:**
```yaml
patches:
- path: flux-pod-anti-affinity.yaml
```

### Why GitOps Patch (Not kubectl patch)

| Method | Persistent | In Git | Survives Reinstall |
|--------|------------|--------|-------------------|
| `kubectl patch` | No | No | No |
| **Kustomize patch** | Yes | Yes | Yes |

### Verification

```bash
# After push, wait ~2-3 min then check
kubectl get pods -n flux-system -o wide
# Pods should be distributed across worker1, worker2, worker3
```

---

## 8b. Ingress Controller Anti-Affinity

Added explicit soft anti-affinity to NGINX Ingress Controller via Helm values.

**Files Modified:**
```
kubernetes/dev/deployments/infrastructure/ingress/helm-release.yaml
kubernetes/prod/deployments/infrastructure/ingress/helm-release.yaml
```

**Helm Values Added:**
```yaml
controller:
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: ingress-nginx
          topologyKey: kubernetes.io/hostname
```

### Why Soft (Preferred) Not Hard (Required)?

| Type | Behavior | Risk |
|------|----------|------|
| **Soft (preferred)** | Spread if possible, but allow same node if needed | None - always schedules |
| **Hard (required)** | Never same node, pod stays Pending if no node | Pod stuck forever |

**We use soft** because availability > perfect distribution.

### What is Weight 100?

Weight (1-100) = priority of this rule. `100` = maximum priority.

If multiple preferences exist, scheduler adds weights to calculate best node.

---

## 9. Lessons Learned

1. **Limits ≠ Usage**: High limits don't mean high actual usage
2. **Plan for growth**: Size prod cluster for all planned workloads
3. **Dev can be small**: Dev only needs to run one app at a time for testing
4. **Monitor early**: Check memory before deploying new applications
5. **Spread critical pods**: Use anti-affinity for controllers (Flux, Ingress)
6. **GitOps for everything**: Even Flux config changes should go through Git
