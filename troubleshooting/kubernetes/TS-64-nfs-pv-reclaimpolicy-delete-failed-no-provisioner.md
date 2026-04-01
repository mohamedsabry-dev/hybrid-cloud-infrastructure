# TS-64: NFS PV Stuck in Failed State — reclaimPolicy Delete Without CSI Provisioner

## Status: RESOLVED
## Date: 2026-04-01
## Severity: Medium
## Environment: k8s-dev / k8s-prod clusters

---

## 1. Issue Summary

`nfs-testing` PersistentVolume entered `Failed` state every time its bound PVC (`testing-storage`) was deleted. The PV could not be reused and Flux reconciliation was blocked. Root cause: `reclaimPolicy: Delete` was set on a static NFS PV with no CSI provisioner installed — Kubernetes attempted to call a delete plugin that did not exist.

---

## 2. Background: How PVC Auto-Binding Works

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

## 3. How the Issue Was Discovered

The `nfs-testing` PV was configured with `reclaimPolicy: Delete` with the intention that deleting the PVC would clean up test data on the NAS automatically.

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

## 4. Root Cause Analysis

```bash
kubectl describe pv nfs-testing
# Events:
#   Warning  VolumeFailedDelete  94s   persistentvolume-controller
#     error getting deleter volume plugin for volume "nfs-testing":
#     no deletable volume plugin matched
```

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

## 5. Additional Discovery: PV Immutability

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

## 6. Recovering a PV Stuck in Failed/Released State

```bash
# Clear the claimRef to return PV to Available
kubectl patch pv nfs-testing -p '{"spec":{"claimRef": null}}'

kubectl get pv nfs-testing
# STATUS: Available
```

---

## 7. Pod ↔ Storage Relationship Clarification

Confirmed through testing:
- **Pod deleted → nothing happens to PVC, PV, or NFS data**
- Pod does not create a folder named after itself — any folder seen on NAS was created by the application running inside the pod
- NFS mount is a **direct mount of the full path** — not per-pod subdirectory like Docker volumes
- Data lifecycle is controlled entirely by PVC/PV, not pod lifecycle

---

## 8. Solution: NFS CSI Driver + Dynamic Provisioning via Flux

### Why CSI Fixes It
Installing `nfs.csi.k8s.io` registers a volume plugin. With it present:
- `reclaimPolicy: Delete` calls the CSI driver → actually deletes the NFS subdirectory
- Dynamic provisioning works — no need to pre-create static PVs per workload

### Files Changed

**`nfs-csi-driver.yaml`** (both dev + prod) — installs the driver via Flux:

> API versions were also corrected here — cluster runs Flux v2.8.3 which dropped `v1beta2`/`v2beta1`

```yaml
apiVersion: source.toolkit.fluxcd.io/v1          # was v1beta2
kind: HelmRepository
metadata:
  name: csi-driver-nfs
  namespace: flux-system
spec:
  interval: 1h
  url: https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
---
apiVersion: helm.toolkit.fluxcd.io/v2            # was v2beta1
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
  share: "/volume1/k8s-prod/testing"    # dev: /volume1/k8s-dev/testing
  onDeletePolicy: delete
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

**`pv.yaml`** — static `nfs-testing` PV removed (CSI driver creates PVs automatically per PVC, with real subdirectory cleanup on deletion).

**`kustomization.yaml`** — `storageclass.yaml` added to resources in both envs.

---

## 9. Why Manual Steps Were Required With Flux

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

## 10. Key Takeaways

| Rule | Detail |
|---|---|
| Static NFS PVs → always use `Retain` | `Delete` requires a CSI provisioner, fails silently with `Failed` status |
| `reclaimPolicy` fires on PVC deletion, not PV deletion | Common naming confusion |
| PV `spec.persistentVolumeSource` is immutable | Must delete + recreate to change `nfs.path`, `capacity`, `accessModes` |
| Pod deletion never affects storage | Data lifecycle = PVC/PV only |
| Flux `prune: true` + protection finalizers = manual cleanup needed | Always drain pods → delete PVC → delete PV before pushing static→dynamic migration |
| Flux v2.8.3 API versions | `source.toolkit.fluxcd.io/v1` and `helm.toolkit.fluxcd.io/v2` — v1beta2/v2beta1 no longer served |
