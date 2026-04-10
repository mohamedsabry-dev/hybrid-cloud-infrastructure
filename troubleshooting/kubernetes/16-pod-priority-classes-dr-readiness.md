# TS-K8S-016 | 2026-04-06 | RESOLVED

## 1. Context
- System: Kubernetes / Pod Scheduling / Priority Classes
- Environment: DEV (k8s-master1.lab.local)
- Related components: All workloads - CSI NFS, Vault Injector, Ingress NGINX, Flux, MariaDB, WordPress, Monitoring
- Discovered during: DR Test 1 preparation - prerequisite assessment

## 2. Issue
- Symptom: Critical infrastructure pods have no priority class configured
- Impact: During node failures or resource pressure, critical pods may be evicted before non-critical ones
- Error: No error - configuration gap discovered during DR readiness assessment

**Required Priority Order (Highest to Lowest):**
```
Priority 1 - Infrastructure (system-node-critical / system-cluster-critical):
    - NFS CSI Driver (storage mounts must be available first)
    - Vault Injector (secrets injection for new pods)
    - Ingress NGINX (external traffic routing)
    - Flux Controllers (GitOps reconciliation)

Priority 2 - Database (database-critical):
    - MariaDB (data layer must be ready before apps)

Priority 3 - Application (app-standard):
    - WordPress (depends on database)

Priority 4 - Monitoring (default/0):
    - Prometheus, Grafana, Alertmanager (observability, non-critical)
```

## 3. Analysis

**Check 1: Available Priority Classes**
```bash
kubectl get priorityclass
```
```
NAME                      VALUE        GLOBAL-DEFAULT   AGE   PREEMPTIONPOLICY
system-cluster-critical   2000000000   false            10d   PreemptLowerPriority
system-node-critical      2000001000   false            10d   PreemptLowerPriority
```
Finding: Only system priority classes exist. Custom classes needed for db/app. ✓

---

**Check 2: CSI NFS Driver Pods**
```bash
kubectl describe pod csi-nfs-controller-7d8bbb9d89-tz5jd -n kube-system | grep -i priority
```
```
Priority:             2000000000
Priority Class Name:  system-cluster-critical
```
Finding: CSI pods have system-cluster-critical. **OK** ✓

---

**Check 3: Vault Injector**
```bash
kubectl describe pod vault-agent-injector-94c4bcc6c-ln296 -n vault | grep -i priority
```
```
Priority:         0
```
Finding: **NO PRIORITY CLASS SET - NEEDS FIX** ✗

---

**Check 4: Ingress NGINX Controller**
```bash
kubectl describe pod ingress-nginx-controller-ccdf84b85-kvw6x -n ingress-nginx | grep -i priority
```
```
Priority:         0
```
Finding: **NO PRIORITY CLASS SET - NEEDS FIX** ✗

---

**Check 5: Flux System Controllers**
```bash
kubectl describe pod helm-controller-844f6958dc-bzqs7 -n flux-system | grep -i priority
kubectl describe pod kustomize-controller-67486f5bfd-hsvmf -n flux-system | grep -i priority
kubectl describe pod source-controller-6d8d58659f-frmw8 -n flux-system | grep -i priority
kubectl describe pod notification-controller-7f5d7cb966-x5ggw -n flux-system | grep -i priority
```
```
helm-controller:          Priority: 2000000000 (system-cluster-critical)
kustomize-controller:     Priority: 2000000000 (system-cluster-critical)
source-controller:        Priority: 2000000000 (system-cluster-critical)
notification-controller:  Priority: 0 (default)
```
Finding: 3/4 Flux controllers have proper priority. notification-controller at default (acceptable). ✓

---

**Check 6: Database (MariaDB)**
```bash
kubectl describe pod mariadb-0 -n database | grep -i priority
```
```
Priority:         0
```
Finding: **NO PRIORITY CLASS SET - NEEDS CUSTOM CLASS** ✗

---

**Check 7: Application (WordPress)**
```bash
kubectl describe pod wordpress-6fbdd48889-r59mb -n apps | grep -i priority
```
```
Priority:         0
```
Finding: **NO PRIORITY CLASS SET - NEEDS CUSTOM CLASS** ✗

---

**Check 8: Monitoring Stack**
```bash
kubectl describe pods -n monitoring | grep -i priority
```
```
Priority: 0 (all 11 pods)
```
Finding: All monitoring pods at default priority. **OK** (lowest priority as expected) ✓

---

**Check 9: Helm Chart Support**
```bash
helm show values vault --repo https://helm.releases.hashicorp.com | grep priorityClassName
helm show values ingress-nginx --repo https://kubernetes.github.io/ingress-nginx | grep priorityClassName
```
```
priorityClassName: ""
```
Finding: Both charts support priorityClassName but not configured. ✓

---

**Findings Summary:**
```
+---------------------------+------------------------+------------+
| Component                 | Current Priority       | Status     |
+---------------------------+------------------------+------------+
| CSI NFS Controller        | system-cluster-critical| OK         |
| CSI NFS Node (DaemonSet)  | system-cluster-critical| OK         |
| Vault Injector            | 0 (default)            | NEEDS FIX  |
| Ingress NGINX             | 0 (default)            | NEEDS FIX  |
| Flux Controllers (3/4)    | system-cluster-critical| OK         |
| Flux notification-ctrl    | 0 (default)            | ACCEPTABLE |
| MariaDB                   | 0 (default)            | NEEDS FIX  |
| WordPress                 | 0 (default)            | NEEDS FIX  |
| Monitoring (all)          | 0 (default)            | OK         |
+---------------------------+------------------------+------------+
```

## 4. Root Cause
> Critical workloads (Vault Injector, Ingress NGINX, MariaDB, WordPress) deployed without priority class configuration. During resource pressure or node failures, these pods would be evicted with same priority as monitoring pods, causing incorrect eviction order and potential service disruption.

## 5. Solution
> Create custom priority classes and configure all workloads appropriately.

**Step 1: Create Custom Priority Classes**

**File:** `kubernetes/deployments/infrastructure/priority-classes.yaml`
```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: database-critical
value: 1000000
globalDefault: false
description: "Database workloads - higher than apps, lower than infrastructure"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: app-standard
value: 500000
globalDefault: false
description: "Application workloads - standard priority"
```

**Step 2: Update Infrastructure Helm Releases**

Vault Injector:
```yaml
injector:
  priorityClassName: system-cluster-critical
```

Ingress NGINX:
```yaml
controller:
  priorityClassName: system-cluster-critical
```

**Step 3: Update Application Workloads**

MariaDB StatefulSet:
```yaml
spec:
  template:
    spec:
      priorityClassName: database-critical
```

WordPress Deployment:
```yaml
spec:
  template:
    spec:
      priorityClassName: app-standard
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact: Pods will be recreated when priority class is added (brief restart)

## 7. Impact After Fix
- Observed: All priorities configured correctly
- Startup/Eviction Order now correct: Storage → Infrastructure → Database → App → Monitoring

**Post-Remediation Validation:**
```
+------------------------+------------+------------------------------------------+
| Priority Class         | Value      | Components                               |
+------------------------+------------+------------------------------------------+
| system-node-critical   | 2000001000 | etcd, apiserver, scheduler, controller,  |
|                        |            | kube-proxy, calico-node, csi-nfs-node    |
+------------------------+------------+------------------------------------------+
| system-cluster-critical| 2000000000 | calico-controllers, coredns, csi-nfs-    |
|                        |            | controller, descheduler, vault-injector, |
|                        |            | ingress-nginx, flux controllers          |
+------------------------+------------+------------------------------------------+
| database-critical      | 1000000    | mariadb                                  |
+------------------------+------------+------------------------------------------+
| app-standard           | 500000     | wordpress                                |
+------------------------+------------+------------------------------------------+
| (default)              | 0          | monitoring stack, notification-controller|
+------------------------+------------+------------------------------------------+
```

## 8. Notes

**Why Priority Classes Matter for DR:**
- During node failure, pods are evicted in priority order (lowest first)
- During resource pressure, lower priority pods are preempted for higher priority
- Incorrect order = database evicted before monitoring = data layer unavailable while dashboards still up

**Verification Command:**
```bash
kubectl describe pod -A | grep -i priority -B 4
```

**Key Points:**
- Monitoring pods should remain at default (0) - they are non-critical and should be evicted first
- Infrastructure must be highest - storage and networking must be available before anything else
- Database before app - data layer must be ready before application layer

## 9. Workaround (if any)
> N/A - must configure priority classes properly for DR readiness.

## References
- DR Test 1 Prerequisites
- [Kubernetes Pod Priority and Preemption](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/)

