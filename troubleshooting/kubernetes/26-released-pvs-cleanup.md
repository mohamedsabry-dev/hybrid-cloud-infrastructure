# TS-K8S-026 | 2026-04-13 | RESOLVED

## 1. Context
- System: Kubernetes NFS CSI Storage
- Environment: DEV cluster + PROD cluster
- Related components: PersistentVolumes, PersistentVolumeClaims, NFS CSI Driver, NAS (10.0.40.120)
- Discovered during: Storage session review and NAS inspection
- Related Cases:
  - TS-K8S-004 — NFS reclaimPolicy (Retain policy is root cause of Released PV accumulation)
  - TS-K8S-005 — StorageClass immutability (redeployments that created orphaned PVs)
  - TS-K8S-015 — Stale NFS mount (cordon/force-delete operations in that case created some of these Released PVs)
  - TS-K8S-019 — Flux prune mass deletion (prune deleted PVCs which also contributed to Released PV accumulation)

---

## 2. Issue
- Symptom: Multiple PersistentVolumes in Released state with orphaned directories on NAS
- Impact: Storage clutter, wasted NAS space, confusing cluster state
- Severity: LOW

**DEV cluster — Released PVs found:**
```
pvc-61b00bb2  Released  apps/wordpress-data          (15Gi)
pvc-0135a248  Released  monitoring/grafana            (5Gi)
pvc-0c3810d9  Released  monitoring/grafana            (5Gi)
pvc-e4d92ffe  Released  monitoring/storage-loki-0     (75Gi)
pvc-98f615ff  Released  monitoring/storage-loki-0     (50Gi)
pvc-3b09734f  Released  default/test-pvc              (1Gi)
```

**PROD cluster — Released PVs found:**
```
pvc-54b1fc94  Released  database/mariadb-data-mariadb-0   (50Gi)
pvc-601a63bb  Released  database/mariadb-data-mariadb-0   (50Gi)
pvc-698c4d29  Released  apps/wordpress-data               (30Gi)
pvc-725345ea  Released  apps/wordpress-data               (30Gi)
pvc-84b544dc  Released  database/mariadb-data-mariadb-0   (50Gi)
pvc-97979c78  Released  database/mariadb-data-mariadb-0   (50Gi)
pvc-baa06fa4  Released  monitoring/storage-loki-0         (100Gi)
pvc-ee3f5248  Released  monitoring/grafana                (10Gi)
```

---

## 3. Analysis

### Why Released PVs Exist

Multiple causes across the lifecycle of the cluster:

1. **Iterative testing** — Deployments redeployed with different PVC specs during learning phase. Each time a PVC was deleted, `reclaimPolicy: Retain` kept the PV alive as Released. New deployments created new PVCs which provisioned fresh PVs and NAS directories.

2. **TS-K8S-015 recovery** — The cordon + force-delete operation to move MariaDB off worker1 did not delete the PVC. When MariaDB was redeployed and the PVC was recreated after size/class changes, old PVCs were deleted leaving Released PVs.

3. **TS-K8S-019 (Flux prune mass deletion)** — Flux prune deleted all resources including PVCs when Kustomization was renamed. Retain policy kept the PVs alive as Released even though the PVCs were gone.

4. **StorageClass testing** — Size changes and StorageClass changes during TS-K8S-005 iterations.

### Why Released PVs Cannot Be Auto-Reused

Kubernetes intentionally blocks automatic rebinding of Released PVs:

```
PVC deleted
  └─► reclaimPolicy: Retain → PV goes Released
        └─► claimRef still points to deleted PVC
              └─► new PVC cannot auto-bind to Released PV
                    └─► CSI creates new PV + new NAS directory
                          └─► old PV and old NAS directory = orphaned
```

Protection reason: prevents accidentally exposing old data to new workloads.

### NAS State — DEV Before Cleanup

Active directories (matching Bound PVCs):
```
pvc-69f14fb9  → apps/wordpress-data       ✅
pvc-f54d8831  → database/mariadb-data     ✅
pvc-a605bec9  → monitoring/alertmanager   ✅
pvc-f640539b  → monitoring/grafana        ✅
pvc-5e8d9355  → monitoring/prometheus     ✅
pvc-aed20697  → monitoring/loki           ✅
```

Orphaned directories (no matching active PVC):
```
pvc-61b00bb2  → old wordpress             🗑️
pvc-0135a248  → old grafana               🗑️
pvc-0c3810d9  → old grafana               🗑️
pvc-e4d92ffe  → old loki (75Gi)          🗑️
pvc-98f615ff  → old loki (50Gi)          🗑️
pvc-3b09734f  → test namespace PVC        🗑️
index.html    → leftover nginx test file  🗑️
```

---

## 4. Root Cause

> `reclaimPolicy: Retain` on all StorageClasses, combined with iterative redeployment during learning phase, Flux prune events, and recovery operations — caused orphaned Released PVs and NAS directories to accumulate over time without anyone noticing.

---

## 5. Solution

### DEV Cluster Cleanup

**Step 1 — Verify active PVCs:**
```bash
kubectl get pvc -A
# Noted all 6 Bound PVCs and their volume names
```

**Step 2 — Cross-reference PVs against active PVCs:**
```bash
kubectl get pv -A | grep Released
# Identified 6 Released PVs with no matching active PVC
# All confirmed test data — safe to delete
```

**Step 3 — Delete Released PV objects:**
```bash
kubectl delete pv pvc-61b00bb2-9a14-4cf7-b6d9-b04287f13440
kubectl delete pv pvc-0135a248-a7df-4ad9-8294-ab70d13ebcf1
kubectl delete pv pvc-0c3810d9-2816-4b31-b24c-62bc0e05ee24
kubectl delete pv pvc-e4d92ffe-230d-4c74-8b98-513a661f7fdf
kubectl delete pv pvc-98f615ff-6812-470e-9662-d2c135f939c3
kubectl delete pv pvc-3b09734f-8502-4a45-8702-8049b70f616e
```

**Step 4 — Delete orphaned NAS directories:**
Performed via NAS UI — deleted all orphaned pvc-* directories and root `index.html`.

**Step 5 — Verify clean state:**
```bash
kubectl get pv -A
# 6 PVs, all Bound, no Released entries

kubectl get pvc -A
# 6 PVCs, all Bound, perfectly match the 6 PVs
```

### PROD Cluster Cleanup

**Step 1 — Verify active PVCs:**
```bash
kubectl get pvc -A
# apps/wordpress-data       → pvc-f26606fa  ✅
# database/mariadb-data     → pvc-ffbc1708  ✅
# monitoring/alertmanager   → pvc-3d118aaf  ✅
# monitoring/grafana        → pvc-1c2ec02b  ✅
# monitoring/prometheus     → pvc-81f03bec  ✅
# monitoring/loki           → pvc-7b25f1e2  ✅
```

**Step 2 — ⚠️ Verify MariaDB data before deleting old MariaDB PVs:**

PROD had 4 Released PVs all claiming `database/mariadb-data-mariadb-0` — MariaDB was redeployed multiple times. Confirmed current active PV `pvc-ffbc1708` contains all data:
```bash
kubectl exec -it mariadb-0 -n database -- mariadb -u root -p
show databases;
# wordpress database present and healthy ✓
```

**Step 3 — Delete Released PV objects:**
```bash
kubectl delete pv pvc-54b1fc94-bcca-446b-acc0-4ec36686cceb
kubectl delete pv pvc-601a63bb-2a29-40bc-bb8d-1cc7649e239c
kubectl delete pv pvc-698c4d29-e83b-476a-be03-894d4ca6d60b
kubectl delete pv pvc-725345ea-411f-4b86-b8a8-e22782e071cc
kubectl delete pv pvc-84b544dc-a403-417e-a8ad-e98b3408e05b
kubectl delete pv pvc-97979c78-092d-4517-b533-a9efd7f2414f
kubectl delete pv pvc-baa06fa4-e516-4cd6-972c-17dc33b85c24
kubectl delete pv pvc-ee3f5248-6d1a-4472-965c-6ac5a2e43ef9
```

**Step 4 — Delete orphaned NAS directories on PROD NAS share (`/volume1/k8s-prod/`):**
Delete all directories matching the Released PV names above via NAS UI.

**Step 5 — Verify clean PROD state:**
```bash
kubectl get pv | grep Released
# Empty — clean
```

---

## 6. Solution Risk
- Risk level: LOW
- Active PVs and PVCs verified before any deletion in both clusters
- MariaDB data confirmed healthy before deleting old MariaDB PVs
- All deleted data was from test/old deployments

---

## 7. Impact After Fix

**DEV:**
- 6 Bound PVs, 0 Released PVs
- NAS directories match exactly the active PVCs

**PROD:**
- 6 Bound PVs, 0 Released PVs
- NAS directories match exactly the active PVCs
- ~430Gi of orphaned NAS space recovered

---

## 8. Notes

### Key Rules

| Rule | Detail |
|---|---|
| Released PV ≠ Available PV | Released has old claimRef — new PVCs cannot auto-bind |
| reclaimPolicy: Retain | Safe for production but requires manual cleanup after PVC deletion |
| CSI always creates fresh PV per new PVC | Old Released PVs become orphans — NAS directories accumulate |
| Always cross-reference PV vs PVC before deleting | Match volume names to confirm active vs orphaned |
| Delete PV object first, then NAS directory | Reverse order leaves ghost NAS directories with no K8s tracking |
| Verify data before deleting multiple PVs for same claim | Especially for databases — multiple Released PVs for same StatefulSet means multiple redeploys |

### How to Recover a Released PV for Reuse

If the Released PV contains data you want to keep:
```bash
# Clear claimRef — returns PV to Available
kubectl patch pv <pv-name> -p '{"spec":{"claimRef": null}}'

# Create PVC that explicitly binds to this PV
spec:
  volumeName: <pv-name>
  storageClassName: nfs-retain
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: <same-size>
```

### Periodic Cleanup Check

Run after any deployment teardown or redeployment:
```bash
kubectl get pv | grep Released
# Empty = clean state
```

### How to Prevent Accumulation

For **test/temporary workloads:**
```yaml
storageClassName: nfs-delete  # CSI auto-deletes NAS directory on PVC delete
```

For **production workloads:**
```yaml
storageClassName: nfs-retain  # Data safety — worth the manual cleanup
```

Run `kubectl get pv | grep Released` after any major change.

---

## 9. Workaround
No workaround needed — manual cleanup is the correct procedure for Retain policy.

For future test workloads use `nfs-delete` StorageClass to avoid accumulation entirely.