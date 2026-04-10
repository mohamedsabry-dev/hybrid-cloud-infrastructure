# TS-K8S-006 | 2026-04-02 | RESOLVED

## 1. Context

- **System:** NFS Storage / Kubernetes / CSI Driver / StorageClass / GitOps
- **Environment:** k8s-dev / k8s-prod clusters
- **Related Components:** NFS CSI driver, StorageClass, PV, PVC, Flux GitOps
- **Discovered During:** NFS storage architecture design and troubleshooting
- **Related:** Case 4 (PV Failed state), Case 5 (StorageClass immutability), Case 3 (NFS Hard Mount)

---

## 2. Issue

**Summary:** This document consolidates the complete NFS storage journey from initial static PV/PVC setup through troubleshooting issues to production-ready dynamic provisioning architecture.

**Journey:**
```
Static PVs (manual) → Failed state issues → CSI Driver installation →
Invalid parameters → Production refactoring → Behavior-based StorageClasses
```

**Issues Encountered:**

### Issue 1: PV Stuck in Failed State (TS-64)

**Symptom:**
```bash
kubectl get pv nfs-testing
# STATUS: Failed
```

**Error:**
```
no deletable volume plugin matched
```

**Cause:** `reclaimPolicy: Delete` on static NFS PV without CSI driver installed.

### Issue 2: StorageClass Invalid Parameter (TS-65)

**Symptom:**
```bash
kubectl describe pvc testing-storage
# invalid parameter "onDeletePolicy" in storage class
```

**Cause:** Used non-existent parameter `onDeletePolicy: delete` in StorageClass.

### Issue 3: StorageClass Parameters Immutable

**Symptom:**
```
Flux dry-run failed: parameters: Forbidden: updates to parameters are forbidden
```

**Cause:** Tried to update existing StorageClass parameters (immutable after creation).

### Issue 4: PVC Infeasible Cache

**Symptom:** PVC stuck in `Pending` even after StorageClass fixed.

**Cause:** Provisioner caches `infeasible` errors on the PVC object itself.

### Issue 5: Flux Recreates Deleted Resources

**Symptom:** Deleted PV/PVC manually, Flux recreated them.

**Cause:** GitOps — git is source of truth. If files exist in git, Flux recreates resources.

**Impact:** Multiple storage architecture issues blocking application deployments.

---

## 3. Analysis

### Concepts Learned

#### StorageClass vs PV vs PVC

| Component | What It Is | Who Creates It | Naming |
|-----------|------------|----------------|--------|
| **StorageClass** | Template/blueprint for storage | Infra team (once) | By behavior: `nfs-retain`, `nfs-delete` |
| **PersistentVolume (PV)** | Actual storage resource | CSI driver (auto) or admin (manual) | Auto: `pvc-xxx-xxx` |
| **PersistentVolumeClaim (PVC)** | App's request for storage | App team/deployment | By app: `prometheus-data`, `nginx-test-data` |

#### Static vs Dynamic Provisioning

| Approach | Flow | Production Use |
|----------|------|----------------|
| **Static** | Admin creates PV → PVC binds to it | 5% (legacy, special cases) |
| **Dynamic** | PVC created → CSI auto-creates PV | 95% (standard) |

#### Why NFS Needs CSI Driver

Kubernetes has no built-in NFS provisioner. Without CSI driver:
- `reclaimPolicy: Delete` causes PV to enter `Failed` state
- No dynamic provisioning possible
- Manual folder management on NFS server

With CSI driver (`nfs.csi.k8s.io`):
- Auto-creates folders on NFS for each PVC
- Auto-deletes folders when PVC deleted (if `Delete` policy)
- Dynamic PV creation

#### Immutability Rules

**PersistentVolume (Immutable After Creation):**
- `nfs.path` / `nfs.server`
- `capacity`
- `accessModes`
- `volumeMode`

**PersistentVolume (Mutable):**
- `persistentVolumeReclaimPolicy`
- `claimRef` (can patch to null to recover stuck PV)

**StorageClass (All Immutable After Creation):**
- `parameters`
- `provisioner`
- `volumeBindingMode`
- `reclaimPolicy`

---

## 4. Root Cause

Multiple interconnected issues:

| Issue | Root Cause |
|-------|------------|
| PV Failed state | `reclaimPolicy: Delete` requires CSI driver for NFS |
| Invalid parameter | `onDeletePolicy` doesn't exist; use `reclaimPolicy` |
| Immutable parameters | StorageClass parameters cannot be updated after creation |
| PVC stuck pending | Provisioner caches infeasible errors on PVC object |
| Flux recreation | GitOps requires git changes before cluster changes |

---

## 5. Solution

### Final Architecture

**Infrastructure Storage Folder:**
```
infrastructure/storage/
├── nfs-csi-driver.yaml      # HelmRepository + HelmRelease
├── storageclass.yaml        # nfs-retain + nfs-delete
└── kustomization.yaml       # References only above 2 files
```

**No PV files. No PVC files.**

### StorageClass Design

**Named by behavior, not by application:**

```yaml
# nfs-retain — for critical/persistent data
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-retain
provisioner: nfs.csi.k8s.io
parameters:
  server: "10.0.40.120"
  share: "/volume1/k8s-prod"    # Base path
reclaimPolicy: Retain            # Keep data on PVC delete
volumeBindingMode: Immediate
mountOptions:
  - soft
  - timeo=30
  - retrans=3
---
# nfs-delete — for temporary/test data
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-delete
provisioner: nfs.csi.k8s.io
parameters:
  server: "10.0.40.120"
  share: "/volume1/k8s-prod"
reclaimPolicy: Delete            # Auto-cleanup on PVC delete
volumeBindingMode: Immediate
mountOptions:
  - soft
  - timeo=30
  - retrans=3
```

### PVCs Live With Apps

```
apps/
├── nginx-test/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── pvc.yaml              # nginx-test-data
│
├── prometheus/
│   └── pvc.yaml              # prometheus-data (uses nfs-retain)
│
└── temp-job/
    └── pvc.yaml              # temp-job-data (uses nfs-delete)
```

### PVC Example

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nginx-test-data        # Named after the app
  namespace: testing
spec:
  storageClassName: nfs-delete # Choose policy
  accessModes:
    - ReadWriteMany            # Defined in PVC, not SC
  resources:
    requests:
      storage: 1Gi
```

### AccessModes

Defined in PVC, NOT StorageClass. NFS supports all:

| Mode | Meaning |
|------|---------|
| `ReadWriteOnce` (RWO) | One node read/write |
| `ReadOnlyMany` (ROX) | Many nodes read-only |
| `ReadWriteMany` (RWX) | Many nodes read/write |

### Issue-Specific Fixes

**Issue 1 Fix:** Install NFS CSI driver OR use `reclaimPolicy: Retain` for static PVs.

**Issue 2 Fix:** Remove `onDeletePolicy`. Use `reclaimPolicy: Delete` on StorageClass itself.

**Issue 3 Fix:** Delete StorageClass manually, then let Flux recreate:
```bash
kubectl delete storageclass <name>
flux reconcile kustomization flux-system --with-source
```

**Issue 4 Fix:** Delete and recreate the PVC:
```bash
kubectl delete pvc <name> -n <namespace>
# Let Flux recreate it
```

**Issue 5 Fix:** Push git changes first, then Flux removes resources automatically. Or suspend Flux:
```bash
flux suspend kustomization flux-system
# Clean up cluster
# Push changes
flux resume kustomization flux-system
```

### Migration Procedure: Static to Dynamic

#### Step 1: Install CSI Driver (if not already)

```yaml
# nfs-csi-driver.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: csi-driver-nfs
  namespace: flux-system
spec:
  interval: 1h
  url: https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: csi-driver-nfs
  namespace: kube-system
spec:
  interval: 1h
  chart:
    spec:
      chart: csi-driver-nfs
      version: ">=4.0.0"
      sourceRef:
        kind: HelmRepository
        name: csi-driver-nfs
        namespace: flux-system
```

#### Step 2: Create StorageClasses

Create `nfs-retain` and `nfs-delete` as shown above.

#### Step 3: Update Files

1. Remove `pv.yaml` from infrastructure/storage
2. Remove `pvc.yaml` from infrastructure/storage
3. Update `kustomization.yaml` to only reference csi-driver and storageclass
4. Create PVC in each app folder with `storageClassName`

#### Step 4: Clean Cluster Before Push

```bash
# Delete old PVCs
kubectl delete pvc monitoring-storage -n monitoring --ignore-not-found
kubectl delete pvc logging-storage -n logging --ignore-not-found
kubectl delete pvc apps-storage -n apps --ignore-not-found
kubectl delete pvc testing-storage -n testing --ignore-not-found

# Delete old PVs
kubectl delete pv nfs-monitoring nfs-logging nfs-apps nfs-testing --ignore-not-found

# Delete old StorageClass (if different name)
kubectl delete sc nfs-csi-testing --ignore-not-found
```

#### Step 5: Push and Reconcile

```bash
git add -A && git commit -m "Refactor: SC-based dynamic provisioning" && git push
flux reconcile kustomization flux-system --with-source
```

#### Step 6: Verify

```bash
kubectl get sc
# NAME         PROVISIONER      RECLAIMPOLICY
# nfs-delete   nfs.csi.k8s.io   Delete
# nfs-retain   nfs.csi.k8s.io   Retain

kubectl get pvc -A
# NAMESPACE   NAME              STATUS   STORAGECLASS
# testing     nginx-test-data   Bound    nfs-delete

kubectl get pv
# NAME                    CAPACITY   RECLAIM POLICY   STATUS   CLAIM
# pvc-xxx-xxx-xxx-xxx     1Gi        Delete           Bound    testing/nginx-test-data
```

### Files Changed

- `infrastructure/storage/nfs-csi-driver.yaml`
- `infrastructure/storage/storageclass.yaml`
- `infrastructure/storage/kustomization.yaml`
- App-specific PVC files in each app folder

### Prevention Measures

1. Always use CSI driver for dynamic NFS provisioning
2. Name StorageClasses by behavior (`nfs-retain`, `nfs-delete`), not by app
3. Keep PVCs with apps, not in infrastructure folder
4. Remember StorageClass parameters are immutable
5. Delete PVC to clear infeasible cache after fixing StorageClass
6. Push git changes before manual cluster cleanup (GitOps)

---

## 6. Solution Risk

- **Risk Level:** Low
- **Potential Impact:**
  - Migration requires deleting existing PVs/PVCs (data loss if not backed up)
  - StorageClass changes require delete + recreate
  - Brief storage unavailability during migration

---

## 7. Impact After Fix

**Observed Results:**

- Dynamic provisioning working for all workloads
- No manual PV management needed
- Clean separation: infrastructure (CSI + SC) vs apps (PVCs)
- Behavior-based naming clarifies data lifecycle
- `soft` mount options prevent pod hangs (Case 3)

**Before vs After:**

### Before (Learning/Static)
```
infrastructure/storage/
├── pv.yaml              # 4 manual PVs
├── pvc.yaml             # 4 manual PVCs
├── nfs-csi-driver.yaml
├── storageclass.yaml    # nfs-csi-testing
└── kustomization.yaml
```

### After (Production/Dynamic)
```
infrastructure/storage/
├── nfs-csi-driver.yaml  # CSI driver
├── storageclass.yaml    # nfs-retain + nfs-delete
└── kustomization.yaml

apps/nginx-test/
└── pvc.yaml             # nginx-test-data → nfs-delete

apps/prometheus/
└── pvc.yaml             # prometheus-data → nfs-retain
```

---

## 8. Notes

### Key Takeaways

| Rule | Detail |
|------|--------|
| Static NFS PVs → use `Retain` only | `Delete` requires CSI driver |
| StorageClass naming → by behavior | `nfs-retain`, `nfs-delete` — NOT `nfs-prometheus` |
| PVCs → live with apps | Not in infrastructure folder |
| One CSI driver → many StorageClasses | Different configs, same provisioner |
| `accessModes` → defined in PVC | Not in StorageClass |
| StorageClass parameters → immutable | Must delete + recreate to change |
| PVC infeasible cache → delete PVC | Fixing SC alone doesn't clear it |
| Flux recreates deleted resources | Push git changes first |
| `flux reconcile --with-source` | Required when stuck on old revision |

### Commands Reference

#### Check CSI driver pods
```bash
kubectl get pods -n kube-system | grep csi
```

#### Check PVC events (why pending)
```bash
kubectl describe pvc <name> -n <namespace> | tail -30
```

#### Check CSI driver logs
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=csi-driver-nfs --tail=50
```

#### Recover stuck PV (clear claimRef)
```bash
kubectl patch pv <name> -p '{"spec":{"claimRef": null}}'
```

#### Force delete stuck PV (remove finalizers)
```bash
kubectl patch pv <name> -p '{"metadata":{"finalizers":null}}'
kubectl delete pv <name>
```

#### Force Flux reconcile with latest git
```bash
flux reconcile kustomization flux-system --with-source
```

### Related Files

- Case 4: NFS PV Stuck in Failed State (reclaimPolicy without provisioner)
- Case 5: StorageClass Invalid Parameter + Flux Stuck
- Case 3: NFS Hard Mount Pod Unresponsiveness
- This document (Case 6): Complete migration guide

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         CLUSTER                                  │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    kube-system namespace                    │ │
│  │                                                             │ │
│  │   ┌─────────────────────────────────────────────────────┐  │ │
│  │   │            NFS CSI Driver Pods                       │  │ │
│  │   │   (installed via HelmRelease, runs on each node)     │  │ │
│  │   └─────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              │                                   │
│              ┌───────────────┴───────────────┐                  │
│              ▼                               ▼                   │
│     ┌─────────────────┐             ┌─────────────────┐         │
│     │   nfs-retain    │             │   nfs-delete    │         │
│     │  StorageClass   │             │  StorageClass   │         │
│     │  (Retain)       │             │  (Delete)       │         │
│     └────────┬────────┘             └────────┬────────┘         │
│              │                               │                   │
│     ┌────────┴────────┐             ┌────────┴────────┐         │
│     │   PVC: app-data │             │ PVC: test-data  │         │
│     │   (prometheus)  │             │ (nginx-test)    │         │
│     └────────┬────────┘             └────────┬────────┘         │
│              │                               │                   │
│     ┌────────┴────────┐             ┌────────┴────────┐         │
│     │ PV: pvc-xxx-xxx │             │ PV: pvc-yyy-yyy │         │
│     │ (auto-created)  │             │ (auto-created)  │         │
│     └────────┬────────┘             └────────┬────────┘         │
│              │                               │                   │
└──────────────┼───────────────────────────────┼───────────────────┘
               │                               │
               ▼                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                       NFS SERVER (10.0.40.120)                   │
│                                                                  │
│  /volume1/k8s-prod/                                             │
│  ├── pvc-xxx-xxx-prometheus-data/    ← Retained on delete       │
│  └── pvc-yyy-yyy-nginx-test-data/    ← Deleted on delete        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 9. Workaround

**If dynamic provisioning is not available:**

**Option A: Use static PVs with `reclaimPolicy: Retain`**
- Create PV manually pointing to NFS path
- Create PVC that binds to specific PV
- Data preserved on PVC delete (manual cleanup required)

**Option B: Install CSI driver**
- Recommended for any production use
- Enables dynamic provisioning
- Supports both Retain and Delete policies

**Note:** Static provisioning should only be used for legacy systems or special cases. Dynamic provisioning with CSI driver is the production standard.
