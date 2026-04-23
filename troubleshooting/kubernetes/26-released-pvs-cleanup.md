# TS-K8S-026 | 2026-04-13 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / Storage
Sub-techs: PersistentVolume, PersistentVolumeClaim, NFS CSI driver, reclaimPolicy Retain,
           Released PV cleanup, NAS storage
Environment: DEV + PROD clusters | NAS 10.0.40.120
Re-opened: No

_____________________________________________________________________

[Issue Description]
Multiple PersistentVolumes in Released state with orphaned directories on NAS.
Storage clutter, wasted NAS space, confusing cluster state. Severity: LOW.

DEV cluster — Released PVs:
  pvc-61b00bb2  15Gi  apps/wordpress-data
  pvc-0135a248   5Gi  monitoring/grafana
  pvc-0c3810d9   5Gi  monitoring/grafana
  pvc-e4d92ffe  75Gi  monitoring/storage-loki-0
  pvc-98f615ff  50Gi  monitoring/storage-loki-0
  pvc-3b09734f   1Gi  default/test-pvc

PROD cluster — Released PVs:
  pvc-54b1fc94  50Gi  database/mariadb-data-mariadb-0
  pvc-601a63bb  50Gi  database/mariadb-data-mariadb-0
  pvc-698c4d29  30Gi  apps/wordpress-data
  pvc-725345ea  30Gi  apps/wordpress-data
  pvc-84b544dc  50Gi  database/mariadb-data-mariadb-0
  pvc-97979c78  50Gi  database/mariadb-data-mariadb-0
  pvc-baa06fa4 100Gi  monitoring/storage-loki-0
  pvc-ee3f5248  10Gi  monitoring/grafana

Related tickets:
  TS-K8S-004 — NFS reclaimPolicy (Retain is root cause of Released PV accumulation)
  TS-K8S-005 — StorageClass immutability (redeployments creating orphaned PVs)
  TS-K8S-015 — Stale NFS mount (cordon/force-delete created some Released PVs)
  TS-K8S-019 — Flux prune mass deletion (prune deleted PVCs, Retain kept PVs alive)

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Identified Released PVs via kubectl get pv and cross-referenced against active PVCs.

Why Released PVs exist — multiple causes:
  1. Iterative testing — deployments redeployed with different PVC specs during
     learning phase. Each PVC deletion left a Released PV. New deployments
     provisioned fresh PVs and NAS directories.
  2. TS-K8S-015 recovery — cordon + force-delete to move MariaDB off worker1.
     PVC recreated after size/class changes left old Released PVs.
  3. TS-K8S-019 Flux prune — prune deleted all PVCs when Kustomization was renamed.
     Retain policy kept PVs alive as Released even though PVCs were gone.
  4. StorageClass changes during TS-K8S-005 iterations.

Why Released PVs cannot be auto-reused:
  PVC deleted → reclaimPolicy Retain → PV goes Released
    → claimRef still points to deleted PVC
    → new PVC cannot auto-bind to Released PV
    → CSI creates new PV + new NAS directory
    → old PV and old NAS directory = orphaned

Protection reason: prevents accidentally exposing old data to new workloads.

NAS state — DEV before cleanup:
  Active (Bound PVCs):
    pvc-69f14fb9  apps/wordpress-data      ✓
    pvc-f54d8831  database/mariadb-data    ✓
    pvc-a605bec9  monitoring/alertmanager  ✓
    pvc-f640539b  monitoring/grafana       ✓
    pvc-5e8d9355  monitoring/prometheus    ✓
    pvc-aed20697  monitoring/loki          ✓

  Orphaned:
    pvc-61b00bb2  old wordpress            orphan
    pvc-0135a248  old grafana              orphan
    pvc-0c3810d9  old grafana              orphan
    pvc-e4d92ffe  old loki 75Gi           orphan
    pvc-98f615ff  old loki 50Gi           orphan
    pvc-3b09734f  test namespace PVC       orphan
    index.html    leftover nginx test file orphan


# Suspected Root Cause
reclaimPolicy: Retain on all StorageClasses combined with iterative redeployment
during learning phase, Flux prune events, and recovery operations caused orphaned
Released PVs and NAS directories to accumulate without anyone noticing.


# More Checks Notes:
PROD had 4 Released PVs all claiming database/mariadb-data-mariadb-0 — MariaDB
was redeployed multiple times. Verified current active PV (pvc-ffbc1708) contains
all data before deleting old Released PVs:

Command:
  kubectl exec -it mariadb-0 -n database -- mariadb -u root -p -e "show databases;"
  → wordpress database present and healthy.


# Suspected Solution
Delete Released PV objects from both clusters. Delete orphaned NAS directories
via NAS UI. Verify clean state after cleanup.


# Test
Ran kubectl get pv after cleanup on both clusters.

Result: PASS
  DEV:  6 PVs, all Bound, 0 Released. NAS matches exactly.
  PROD: 6 PVs, all Bound, 0 Released. ~430Gi orphaned space recovered.

_____________________________________________________________________

[Final Root Cause]
reclaimPolicy: Retain on all StorageClasses kept PVs alive as Released after
PVC deletions from multiple causes (testing iterations, Flux prune, recovery
operations). CSI always creates a fresh PV and NAS directory per new PVC —
old Released PVs and their NAS directories accumulated silently over time.

_____________________________________________________________________

[Final Solution]

DEV cleanup:
  Step 1 — Verify active PVCs: kubectl get pvc -A → 6 Bound PVCs noted
  Step 2 — Cross-reference against Released PVs: kubectl get pv | grep Released
  Step 3 — Delete 6 Released PV objects: kubectl delete pv <pv-name> (×6)
  Step 4 — Delete orphaned NAS directories via NAS UI (/volume1/k8s-dev/)
  Step 5 — Verify: kubectl get pv → 6 PVs, all Bound, 0 Released

PROD cleanup:
  Step 1 — Verify active PVCs (6 Bound confirmed)
  Step 2 — Verify MariaDB data before deleting old MariaDB PVs (4 Released PVs
           all claiming same StatefulSet — multiple redeploys)
           kubectl exec -it mariadb-0 -n database -- mariadb -u root -p
           show databases → wordpress database healthy
  Step 3 — Delete 8 Released PV objects: kubectl delete pv <pv-name> (×8)
  Step 4 — Delete orphaned NAS directories via NAS UI (/volume1/k8s-prod/)
  Step 5 — Verify: kubectl get pv → 6 PVs, all Bound, 0 Released

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Active PVs and PVCs verified before any deletion in both clusters.
MariaDB data confirmed healthy before deleting old MariaDB PVs.
All deleted data was from test or old deployments.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Key rules for PV cleanup:
  Released PV ≠ Available PV  — Released has old claimRef, new PVCs cannot auto-bind
  reclaimPolicy: Retain       — safe for prod but requires manual cleanup after PVC deletion
  CSI always creates fresh PV — old Released PVs accumulate, NAS directories pile up
  Cross-reference before deleting — match volume names to confirm active vs orphaned
  Delete PV object first, then NAS directory — reverse order leaves ghost directories
  Verify data before deleting multiple PVs for same StatefulSet claim

How to recover a Released PV for reuse (if data should be kept):
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

Periodic cleanup check (run after any deployment teardown or redeployment):
  kubectl get pv | grep Released  → should be empty

Prevention going forward:
  Test/temporary workloads  → storageClassName: nfs-delete (CSI auto-deletes on PVC delete)
  Production workloads      → storageClassName: nfs-retain (data safety, manual cleanup)