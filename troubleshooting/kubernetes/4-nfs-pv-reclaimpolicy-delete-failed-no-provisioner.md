# TS-K8S-004 | 2026-04-01 | RESOLVED

## 1. Context
- System: Kubernetes / PersistentVolume / NFS Storage
- Environment: k8s-dev / k8s-prod clusters
- Related components: Static NFS PV, Flux GitOps, NFS CSI Driver
- Discovered during: Testing PVC deletion and recreation workflow
- Related Cases:
  - TS-K8S-005 — StorageClass immutability (next failure in the migration chain)
  - TS-K8S-006 — Complete NFS storage guide (final architecture from this journey)
  - TS-K8S-026 — Released PV cleanup (orphaned PVs from Retain policy accumulate over time)

---

## 2. Issue
- Symptom: `nfs-testing` PersistentVolume stuck in `Failed` state after PVC deletion
- Error: `no deletable volume plugin matched`
- Impact: PV could not be reused; Flux reconciliation blocked

The PV was configured with `reclaimPolicy: Delete` with the intention that deleting the PVC would clean up test data on the NAS automatically.

```yaml
# pv.yaml (original)
spec:
  persistentVolumeReclaimPolicy: Delete
  nfs:
    server: 10.0.40.120
    path: /volume1/k8s-prod/testing
```

After deleting the PVC:
```bash
kubectl delete pvc testing-storage -n testing
kubectl get pv nfs-testing
# NAME          STATUS   CLAIM                      STORAGECLASS
# nfs-testing   Failed   testing/testing-storage
```

PV was stuck in `Failed` and still referenced the deleted PVC. NFS data on the NAS was **not** deleted.

---

## 3. Analysis

### Check 1: Describe PV for Events

```bash
kubectl describe pv nfs-testing
# Events:
#   Warning  VolumeFailedDelete  94s   persistentvolume-controller
#     error getting deleter volume plugin for volume "nfs-testing":
#     no deletable volume plugin matched
```

Finding: K8s tried to call a delete plugin but none exists for static NFS volumes.

---

### Check 2: Understanding reclaimPolicy Behavior

**reclaimPolicy naming causes confusion** — it sounds like it fires when the PV is deleted, but it actually fires when the **PVC unbinds** (i.e. PVC is deleted or released).

The policy name means: *"what to do with the PV when it gets reclaimed (freed from a claim)"*

| Policy | Triggers on PVC deletion | Result |
|---|---|---|
| `Retain` | PV stays as `Released` | Data safe, manual cleanup needed |
| `Delete` | PV deleted + tries to wipe backend | Requires CSI/provisioner |

K8s treats PVC deletion as the end-of-lifecycle signal for the storage. When `Delete` is set:
1. PVC deleted → K8s sees PV is now unclaimed
2. Triggers reclaim → looks for a volume delete plugin matching the PV's source type
3. No NFS CSI driver installed → `no deletable volume plugin matched` → `Failed`
4. PV stuck: still holds old `claimRef`, status `Failed`, cannot rebind

**NFS data on the NAS was completely untouched** — the `Failed` state is a provisioner call failure only.

---

### Check 3: What Happens to NAS When a Static PV Is Deleted

When you manually delete a static PV (`kubectl delete pv <name>`), Kubernetes removes the PV object from the cluster. The NAS directory is **never touched** — no delete operation is sent to the storage backend for static PVs regardless of reclaimPolicy.

```
kubectl delete pv nfs-testing
  └─► PV object removed from cluster
        └─► NAS directory /volume1/k8s-prod/testing: UNTOUCHED
              └─► must be deleted manually on the NAS
```

Only the NFS CSI driver with `reclaimPolicy: Delete` on a **dynamically provisioned** PV can actually delete the NAS subdirectory automatically. Static PVs never get automatic NAS cleanup — see TS-K8S-026 for how this causes orphaned directories to accumulate.

---

### Check 4: PVC Binding Behavior (Background)

Before hitting the issue, the following was confirmed through CLI testing:

**If no `storageClassName` is set on a PVC:**
- If a default StorageClass exists → K8s binds using that class + `accessModes` + `capacity`
- If no default StorageClass exists (this lab) → PVC only binds to PVs that also have **no** `storageClassName` set

Binding precedence: `storageClassName match → accessModes → capacity`

Verified by:
```bash
kubectl get storageclass
# No (default) annotation present → no default StorageClass in cluster
```

**A PVC that is already bound cannot be re-evaluated** — `kubectl apply` on a bound PVC only patches annotations, it does not trigger rebinding. Must delete and recreate the PVC to test new binding behavior.

---

### Check 5: PV Immutability Discovery

While attempting to fix by editing the PV:
```bash
kubectl apply -f pv.yaml   # with modified nfs.path
# Error: spec.persistentVolumeSource is immutable after creation
```

**Fields immutable after PV creation:**
- `nfs.path` / `nfs.server`
- `capacity`
- `accessModes`
- `volumeMode`

**Fields mutable on a live PV:**
- `persistentVolumeReclaimPolicy` — can be patched in-place
- `claimRef` — can be patched to null to recover a stuck PV

---

### Check 6: Recovering a Stuck PV

```bash
# Clear the claimRef to return PV to Available
kubectl patch pv nfs-testing -p '{"spec":{"claimRef": null}}'

kubectl get pv nfs-testing
# STATUS: Available
```

---

### Check 7: Pod ↔ Storage Relationship Clarification

Confirmed through testing:
- **Pod deleted → nothing happens to PVC, PV, or NFS data**
- **Deployment deleted → nothing happens to PVC, PV, or NFS data**
- Pod does not create a folder named after itself — any folder seen on NAS was created by the application running inside the pod
- NFS mount is a **direct mount of the full path** — not per-pod subdirectory like Docker volumes
- Data lifecycle is controlled entirely by PVC/PV, not pod or deployment lifecycle

---

## 4. Root Cause
> `reclaimPolicy: Delete` was set on a static NFS PV without an NFS CSI provisioner installed. When PVC was deleted, Kubernetes attempted to call a delete plugin that did not exist, causing the PV to enter Failed state with `no deletable volume plugin matched`.

---

## 5. Solution

### Why CSI Fixes It
Installing `nfs.csi.k8s.io` registers a volume plugin. With it present:
- `reclaimPolicy: Delete` calls the CSI driver → actually deletes the NFS subdirectory
- Dynamic provisioning works — no need to pre-create static PVs per workload

### Files Changed

**`nfs-csi-driver.yaml`** (both dev + prod) — installs the driver via Flux:

```yaml
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

**`storageclass.yaml`** (new file, both dev + prod) — enables dynamic provisioning:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-csi-testing
provisioner: nfs.csi.k8s.io
parameters:
  server: "10.0.40.120"
  share: "/volume1/k8s-prod/testing"
reclaimPolicy: Delete
volumeBindingMode: Immediate
mountOptions:
  - soft
  - timeo=30
  - retrans=3
```

**`pvc.yaml`** — `testing-storage` migrated from static to dynamic:

```yaml
# Before (static binding to named PV):
spec:
  volumeName: nfs-testing

# After (dynamic via StorageClass):
spec:
  storageClassName: nfs-csi-testing
```

**`pv.yaml`** — static `nfs-testing` PV removed (CSI driver creates PVs automatically per PVC).

### Why Manual Steps Were Required With Flux

Flux with `prune: true` will **try** to delete the old static PV once removed from git — but it will hang in `Terminating` forever due to Kubernetes protection finalizers:

- `kubernetes.io/pvc-protection` — blocks PVC deletion while a pod is mounting it
- `kubernetes.io/pv-protection` — blocks PV deletion while a PVC is bound to it

Flux cannot override these. It retries indefinitely and blocks reconciliation of the new dynamic resources.

**Correct migration order before pushing git changes:**

```bash
# 1. Delete pods using the PVC (removes pvc-protection finalizer blocker)
kubectl delete pods -n testing --all

# 2. Delete the PVC (removes pv-protection finalizer blocker)
kubectl delete pvc testing-storage -n testing

# 3. Delete the static PV manually
kubectl delete pv nfs-testing

# 4. Push git changes
# Flux reconciles → StorageClass created → dynamic PVC created →
# CSI driver provisions PV + NFS subdirectory automatically
```

Skipping step 1 → PVC stuck in `Terminating` → PV stuck in `Terminating` → Flux reconciliation blocked entirely.

---

## 6. Solution Risk
- Risk level: MEDIUM
- Potential impact: Static to dynamic migration requires manual cleanup before git push; brief storage unavailability during migration

---

## 7. Impact After Fix
- Observed: Dynamic provisioning working correctly
- PVC deletion now properly deletes NFS subdirectory via CSI driver
- No more `Failed` PV states

---

## 8. Notes

### Key Takeaways

| Rule | Detail |
|---|---|
| Static NFS PVs → always use `Retain` | `Delete` requires a CSI provisioner, fails silently with `Failed` status |
| `reclaimPolicy` fires on PVC deletion, not PV deletion | Common naming confusion |
| Deleting a static PV never touches NAS | NAS directory must be deleted manually regardless of reclaimPolicy |
| PV `spec.persistentVolumeSource` is immutable | Must delete + recreate to change `nfs.path`, `capacity`, `accessModes` |
| Pod/Deployment deletion never affects storage | Data lifecycle = PVC/PV only |
| Flux `prune: true` + protection finalizers = manual cleanup needed | Always drain pods → delete PVC → delete PV before pushing static→dynamic migration |
| Flux v2.8.3 API versions | `source.toolkit.fluxcd.io/v1` and `helm.toolkit.fluxcd.io/v2` — v1beta2/v2beta1 no longer served |

### Quick Recovery Commands

```bash
# Clear claimRef to return Failed/Released PV to Available
kubectl patch pv <pv-name> -p '{"spec":{"claimRef": null}}'

# Check PV status
kubectl get pv
kubectl describe pv <pv-name>

# Check protection finalizers
kubectl get pvc -o yaml | grep -A5 finalizers
```

---

## 9. Workaround (if any)
> For static NFS PVs, change `reclaimPolicy` from `Delete` to `Retain`:
> ```bash
> kubectl patch pv nfs-testing -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
> ```
> Then manually clear `claimRef` when ready to reuse.