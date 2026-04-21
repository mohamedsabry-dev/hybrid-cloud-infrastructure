# TS-K8S-006 | 2026-04-02 | RESOLVED
> Last updated: 2026-04-13 — added nfs-database StorageClass (TS-K8S-015), controller placement clarification (TS-K8S-018), Released PV cleanup procedure (TS-K8S-026)

## 1. Context

- **System:** NFS Storage / Kubernetes / CSI Driver / StorageClass / GitOps
- **Environment:** k8s-dev / k8s-prod clusters
- **Related Components:** NFS CSI driver, StorageClass, PV, PVC, Flux GitOps
- **Discovered During:** NFS storage architecture design and troubleshooting
- **Related Cases:**
  - TS-K8S-003 — NFS hard mount causing pod hangs (mountOptions requirement)
  - TS-K8S-004 — PV Failed state with reclaimPolicy:Delete without CSI
  - TS-K8S-005 — StorageClass parameter immutability
  - TS-K8S-007 — InnoDB O_DIRECT incompatibility with NFS
  - TS-K8S-015 — Stale NFS mount on CSI restart (introduced nfs-database StorageClass)
  - TS-K8S-018 — CSI controller network placement in segmented environments
  - TS-K8S-026 — Released PV accumulation and cleanup procedure

---

## 2. Journey Summary

```
Static PVs (manual) → Failed state (TS-K8S-004) → CSI Driver installation →
Invalid parameters (TS-K8S-005) → Production refactoring → Behavior-based StorageClasses →
Network placement issue (TS-K8S-018) → Database mount options (TS-K8S-015) →
Released PV cleanup (TS-K8S-026)
```

---

## 3. Concepts

### StorageClass vs PV vs PVC

| Component | What It Is | Who Creates It | Naming Convention |
|-----------|------------|----------------|-------------------|
| **StorageClass** | Template/blueprint for storage | Infra team (once) | By behavior: `nfs-retain`, `nfs-delete`, `nfs-database` |
| **PersistentVolume (PV)** | Actual storage resource | CSI driver (auto) | Auto: `pvc-<uuid>` |
| **PersistentVolumeClaim (PVC)** | App's request for storage | App team/deployment | By app: `prometheus-data`, `mariadb-data` |

### Static vs Dynamic Provisioning

| Approach | Flow | Production Use |
|----------|------|----------------|
| **Static** | Admin creates PV manually → PVC binds to it | Legacy only |
| **Dynamic** | PVC created → CSI auto-creates PV | Standard — use this |

### How CSI Creates NFS Subdirectories

The StorageClass `share` parameter is the **base path** on the NAS. CSI does not use this path directly — it creates a subdirectory under it named `pvc-<uuid>` for each PVC.

```
StorageClass parameter: share: "/volume1/k8s-prod"
PVC created: mariadb-data
  └─► CSI creates: /volume1/k8s-prod/pvc-ffbc1708-252f-48f8-bd87-70ee37726bc8/
        └─► PV created pointing to that subdirectory
              └─► PVC bound to PV
```

NAS directory names are always `pvc-<uuid>` — never human-readable app names. This is why NAS inspection shows UUID-named directories.

### Why NFS Needs CSI Driver

Kubernetes has no built-in NFS provisioner. Without CSI driver:
- `reclaimPolicy: Delete` causes PV to enter `Failed` state (TS-K8S-004)
- No dynamic provisioning possible
- Manual NAS folder management required
- Deleting a static PV never touches the NAS directory

With CSI driver (`nfs.csi.k8s.io`):
- Auto-creates subdirectory on NAS for each PVC
- Auto-deletes subdirectory when PVC deleted (if `Delete` policy)
- Dynamic PV creation — no manual PV management

### Immutability Rules

**PersistentVolume (Immutable After Creation):**
- `nfs.path` / `nfs.server`
- `capacity`
- `accessModes`
- `volumeMode`

**PersistentVolume (Mutable):**
- `persistentVolumeReclaimPolicy` — patch in-place
- `claimRef` — patch to null to recover stuck/Released PV

**StorageClass (All Immutable After Creation):**
- `parameters`
- `provisioner`
- `volumeBindingMode`
- `reclaimPolicy`

---

## 4. Final Architecture

### Infrastructure Storage Folder

```
infrastructure/storage/
├── nfs-csi-driver.yaml      # HelmRepository + HelmRelease
├── storageclass.yaml        # nfs-retain + nfs-delete + nfs-database
└── kustomization.yaml
```

**No PV files. No PVC files in infrastructure.**

### StorageClass Design — Three Classes by Behavior

```yaml
# nfs-retain — critical/persistent data (WordPress, MariaDB, Prometheus, Grafana, Loki)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-retain
provisioner: nfs.csi.k8s.io
parameters:
  server: "10.0.40.120"
  share: "/volume1/k8s-prod"    # base path — CSI creates pvc-<uuid> subdirs under here
reclaimPolicy: Retain
volumeBindingMode: Immediate
mountOptions:
  - nfsvers=3
  - nolock
  - soft
  - timeo=30
  - retrans=3
---
# nfs-delete — temporary/test data (cleaned up automatically on PVC delete)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-delete
provisioner: nfs.csi.k8s.io
parameters:
  server: "10.0.40.120"
  share: "/volume1/k8s-prod"
reclaimPolicy: Delete
volumeBindingMode: Immediate
mountOptions:
  - nfsvers=3
  - nolock
  - soft
  - timeo=30
  - retrans=3
---
# nfs-database — databases requiring write integrity on NFS (MariaDB, PostgreSQL)
# Added in TS-K8S-015 after soft mount caused MariaDB CrashLoopBackOff
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-database
provisioner: nfs.csi.k8s.io
parameters:
  server: "10.0.40.120"
  share: "/volume1/k8s-prod"
reclaimPolicy: Retain
volumeBindingMode: Immediate
mountOptions:
  - nfsvers=3
  - nolock
  - hard
  - timeo=600
  - retrans=5
  - intr
```

### Mount Options Decision Table

| Workload | StorageClass | Mount Options | Reason |
|---|---|---|---|
| WordPress, Nginx, static apps | nfs-retain | soft, timeo=30, retrans=3 | Crash + restart better than silent hang |
| Prometheus, Grafana, Loki | nfs-retain | soft, timeo=30, retrans=3 | Can rescrape, should not hang cluster |
| MariaDB, PostgreSQL | nfs-database | hard, timeo=600, retrans=5, intr | Data integrity critical — see TS-K8S-007/015 |
| Temp/test workloads | nfs-delete | soft, timeo=30, retrans=3 | Auto-cleanup on PVC delete |

### PVCs Live With Apps

```
apps/wordpress/
└── pvc.yaml              # storageClassName: nfs-retain

apps/mariadb/
└── statefulset.yaml      # volumeClaimTemplate → storageClassName: nfs-database

monitoring/prometheus/
└── values or pvc.yaml    # storageClassName: nfs-retain

testing/nginx-test/
└── pvc.yaml              # storageClassName: nfs-delete
```

### PVC Example

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nginx-test-data
  namespace: testing
spec:
  storageClassName: nfs-delete
  accessModes:
    - ReadWriteMany      # defined in PVC, not StorageClass
  resources:
    requests:
      storage: 1Gi
```

### AccessModes

Defined in PVC, NOT StorageClass. NFS supports all:

| Mode | Meaning | Use case |
|------|---------|----------|
| `ReadWriteOnce` (RWO) | One node read/write | Databases, single-instance apps |
| `ReadOnlyMany` (ROX) | Many nodes read-only | Static content |
| `ReadWriteMany` (RWX) | Many nodes read/write | Shared content, multi-replica apps |

---

## 5. CSI Driver Architecture

### Two Components, Two Responsibilities

```
csi-nfs-controller (Deployment)
  replicas: 2
  runs on: worker nodes (NOT masters — see TS-K8S-018)
  responsibility: CREATE and DELETE NFS subdirectories
  called when: PVC is created or deleted
  needs: network access to NFS server (10.0.40.x)

csi-nfs-node (DaemonSet)
  runs on: every node (or workers only if masters have no NFS access)
  responsibility: MOUNT and UNMOUNT NFS paths on the node
  called when: pod is scheduled to that node and needs NFS volume
  communicates with: kubelet via unix socket on same node
```

### Controller Node Placement — Critical in Network-Segmented Environments

**In this lab, masters (10.0.61.x) have no route to NFS storage (10.0.40.x). Workers (10.0.64.x) have dedicated storage NICs.**

CSI controller must run on workers — it temporarily mounts NFS during PVC provisioning to create subdirectories. If it runs on masters, provisioning fails with mount timeout (TS-K8S-018).

```yaml
# HelmRelease values — controller on workers only
controller:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: node-role.kubernetes.io/control-plane
                operator: DoesNotExist  # DoesNotExist = workers only
```

**Note:** `DoesNotExist` targets workers (nodes WITHOUT control-plane label). `Exists` targets masters. Verify placement after applying:
```bash
kubectl get pods -n kube-system -o wide | grep csi-nfs-controller
# Must show worker nodes, not masters
```

**Limitation:** If all workers are down, CSI controller cannot provision new PVCs — no failover to masters due to network isolation. Existing mounts on pods are unaffected.

### CSI Node DaemonSet

The csi-nfs-node DaemonSet runs one pod per node. If your design keeps NFS access on workers only, restrict the DaemonSet to workers:

```yaml
node:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: node-role.kubernetes.io/control-plane
                operator: DoesNotExist
```

This reduces from 6 pods (3 masters + 3 workers) to 3 pods (workers only).

### When CSI Controller Is Down

- No new PVC provisioning
- No PVC deletion (NAS subdirectory not removed)
- Existing running pods with mounted volumes: **unaffected**
- The mount was established at pod start by csi-nfs-node — controller not involved after that

---

## 6. Released PV Accumulation

Released PVs accumulate when PVCs are deleted with `reclaimPolicy: Retain`. The PV stays alive but cannot be automatically rebound to new PVCs — it still holds the old `claimRef`.

```
PVC deleted
  └─► reclaimPolicy: Retain → PV goes Released
        └─► claimRef still points to deleted PVC
              └─► new PVC cannot auto-bind to Released PV
                    └─► CSI creates new PV + new NAS directory
                          └─► old PV and old NAS directory = orphaned
```

**Periodic check command:**
```bash
kubectl get pv | grep Released
# Empty output = clean state
```

**Cleanup procedure:**
```bash
# 1. Identify Released PVs
kubectl get pv -A | grep Released

# 2. Cross-reference against active PVCs
kubectl get pvc -A
# Match VOLUME field of active PVCs against Released PV names

# 3. Delete Released PV objects
kubectl delete pv <pv-name>

# 4. Delete orphaned NAS directories manually via NAS UI or SSH
```

**Recover a Released PV for reuse (if data still needed):**
```bash
kubectl patch pv <pv-name> -p '{"spec":{"claimRef": null}}'
# Then create PVC with spec.volumeName: <pv-name> to bind explicitly
```

See TS-K8S-026 for the full cleanup case with real examples.

---

## 7. Migration: Static to Dynamic

```bash
# Step 1: Install CSI driver via Flux (nfs-csi-driver.yaml)

# Step 2: Create StorageClasses (storageclass.yaml)

# Step 3: Update app PVC files to use storageClassName

# Step 4: Clean cluster before pushing git
kubectl delete pvc <old-pvcs> --ignore-not-found
kubectl delete pv <old-pvs> --ignore-not-found
kubectl delete sc <old-sc> --ignore-not-found

# Step 5: Push and reconcile
git add -A && git commit -m "Refactor: dynamic NFS provisioning" && git push
flux reconcile kustomization infrastructure --with-source

# Step 6: Verify
kubectl get sc
kubectl get pvc -A
kubectl get pv
```

---

## 8. Lessons Learned

| Rule | Detail |
|------|--------|
| Static NFS PVs → use `Retain` only | `Delete` requires CSI driver — TS-K8S-004 |
| StorageClass naming → by behavior | `nfs-retain`, `nfs-delete`, `nfs-database` — not by app |
| PVCs → live with apps | Not in infrastructure folder |
| StorageClass `share` = base path | CSI creates `pvc-<uuid>` subdirs under it — not human-readable names |
| `accessModes` → defined in PVC | Not in StorageClass |
| StorageClass parameters → immutable | Must delete + recreate — TS-K8S-005 |
| PVC infeasible cache → delete PVC | Fixing SC alone doesn't clear it — TS-K8S-005 |
| CSI controller needs NFS network access | Must run on workers if masters have no storage route — TS-K8S-018 |
| soft mount for stateless apps | TS-K8S-003 |
| hard mount for databases | TS-K8S-007, TS-K8S-015 |
| Released PVs accumulate silently | Run `kubectl get pv | grep Released` periodically — TS-K8S-026 |
| Deleting static PV never touches NAS | Must manually delete NAS directory — TS-K8S-004 |

---

## 9. Commands Reference

```bash
# Check CSI driver pods and location
kubectl get pods -n kube-system -o wide | grep csi

# Check PVC events (why pending)
kubectl describe pvc <n> -n <namespace> | tail -30

# Check CSI driver logs
kubectl logs -n kube-system -l app.kubernetes.io/name=csi-driver-nfs --tail=50

# Recover stuck PV (clear claimRef)
kubectl patch pv <n> -p '{"spec":{"claimRef": null}}'

# Force delete stuck PV (remove finalizers)
kubectl patch pv <n> -p '{"metadata":{"finalizers":null}}'
kubectl delete pv <n>

# Force Flux reconcile with latest git
flux reconcile kustomization infrastructure --with-source

# Periodic Released PV check
kubectl get pv | grep Released
```