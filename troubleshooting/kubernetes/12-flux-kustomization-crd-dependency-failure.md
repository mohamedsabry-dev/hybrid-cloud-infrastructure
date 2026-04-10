# TS-K8S-012 | 2026-04-05 | RESOLVED

## 1. Context

- **System:** Kubernetes cluster with FluxCD GitOps
- **Environment:** Development cluster (dev)
- **Related Components:** Flux Kustomization controller, kube-prometheus-stack HelmRelease, ServiceMonitor CRD
- **Discovered During:** Application deployment via Flux GitOps synchronization

## 2. Issue

**Symptom:** ServiceMonitor resources fail to deploy because the Custom Resource Definition (CRD) from kube-prometheus-stack is not yet installed when Flux tries to apply them.

**Error:**
```bash
$ flux get kustomization
NAME          REVISION              SUSPENDED  READY  MESSAGE
deployments   dev@sha1:0a512c5d     False      False  ServiceMonitor/apps/wordpress dry-run failed: no matches for kind "ServiceMonitor" in version "monitoring.coreos.com/v1"
```

**Impact:** Application deployments (wordpress, mariadb) fail to reconcile. Monitoring integration via ServiceMonitors is blocked until CRDs are available.

## 3. Analysis

### Step 1: Identify the failing resource
```bash
$ flux get kustomization
# Look for READY: False and check the MESSAGE column
```

### Step 2: Verify CRD existence
```bash
$ kubectl get crd servicemonitors.monitoring.coreos.com
# Error: the server doesn't have a resource type "servicemonitors"
```

### Step 3: Check if monitoring stack is deployed
```bash
$ kubectl get helmrelease -n monitoring
# No resources found OR HelmRelease exists but not ready
```

### Step 4: Check monitoring kustomization resources
```bash
$ cat kubernetes/dev/deployments/apps/monitoring/kustomization.yaml
# Verify resources are listed (not empty)
```

**Evidence from session:**
```yaml
# monitoring/kustomization.yaml was empty:
resources: []
# Add prometheus, grafana here when ready
```

## 4. Root Cause

Flux applies all resources in a Kustomization simultaneously. When ServiceMonitor resources are defined in app deployments (wordpress, mariadb), but the kube-prometheus-stack HelmRelease (which installs the ServiceMonitor CRD) is in the same Kustomization, the CRD may not be installed before the ServiceMonitor resources are applied.

The monitoring kustomization was empty, meaning the kube-prometheus-stack that provides the ServiceMonitor CRD was never deployed, yet application deployments referenced ServiceMonitor resources.

## 5. Solution

### Option A: Temporary Fix (Quick)
Comment out ServiceMonitors until monitoring stack deploys:
```yaml
# kubernetes/dev/deployments/apps/wordpress/kustomization.yaml
resources:
  - deployment.yaml
  # - servicemonitor.yaml  # Enable after kube-prometheus-stack is deployed
```

### Option B: Permanent Fix (Recommended)
Create separate Flux Kustomizations with dependencies:

**1. Create infrastructure-sync.yaml:**
```yaml
# kubernetes/dev/flux/infrastructure-sync.yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure
  namespace: flux-system
spec:
  interval: 5m0s
  path: ./kubernetes/dev/deployments/apps/monitoring
  prune: true
  wait: true  # Critical: wait for all resources to be ready
  sourceRef:
    kind: GitRepository
    name: flux-system
```

**2. Update deployments-sync.yaml:**
```yaml
# kubernetes/dev/flux/deployments-sync.yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: deployments
  namespace: flux-system
spec:
  dependsOn:
    - name: infrastructure  # Wait for monitoring stack first
  interval: 5m0s
  path: ./kubernetes/dev/deployments
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
```

**3. Update flux kustomization.yaml:**
```yaml
# kubernetes/dev/flux/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - flux-system
  - infrastructure-sync.yaml
  - deployments-sync.yaml
```

**4. Remove monitoring from apps kustomization:**
```yaml
# kubernetes/dev/deployments/apps/kustomization.yaml
resources:
  # monitoring is deployed via infrastructure-sync.yaml
  - logging
  - testing
  - mariadb
  - wordpress
```

### Prevention Measures
- Always use separate Flux Kustomizations for infrastructure (CRDs, operators) and applications
- Use `dependsOn` to enforce deployment order
- Use `wait: true` on infrastructure Kustomizations to ensure CRDs are fully installed

## 6. Solution Risk

- **Risk Level:** Low
- **Potential Impact:** Temporary deployment interruption during Flux Kustomization restructuring. Applications may need to be re-reconciled after the change.

## 7. Impact After Fix

**Observed Results:**
```bash
# Check kustomizations
$ flux get kustomization
NAME            READY  MESSAGE
infrastructure  True   Applied revision: dev@sha1:xxxxx
deployments     True   Applied revision: dev@sha1:xxxxx

# Verify CRD exists
$ kubectl get crd servicemonitors.monitoring.coreos.com
NAME                                    CREATED AT
servicemonitors.monitoring.coreos.com   2026-04-05T18:xx:xxZ

# Verify ServiceMonitors are created
$ kubectl get servicemonitor -A
NAMESPACE  NAME        AGE
apps       wordpress   1m
database   mariadb     1m
```

## 8. Notes

### Lessons Learned
- CRDs must be deployed before resources that depend on them
- Flux Kustomization `dependsOn` is essential for ordering deployments
- The `wait: true` option ensures CRDs are fully registered before dependent Kustomizations start

### Commands Reference
```bash
flux get kustomization                                    # Check Flux sync status
kubectl get crd servicemonitors.monitoring.coreos.com    # Verify CRD existence
kubectl get servicemonitor -A                             # List all ServiceMonitors
```

### Related Files
- `kubernetes/dev/flux/infrastructure-sync.yaml`
- `kubernetes/dev/flux/deployments-sync.yaml`
- `kubernetes/dev/flux/kustomization.yaml`
- `kubernetes/dev/deployments/apps/kustomization.yaml`

## 9. Workaround

**Temporary:** Comment out ServiceMonitor resources from application kustomizations until the monitoring stack with CRDs is deployed:
```yaml
resources:
  - deployment.yaml
  # - servicemonitor.yaml  # Uncomment after kube-prometheus-stack is ready
```
