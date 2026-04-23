# TS-K8S-004 | 2026-04-01 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / PersistentVolume / NFS Storage
Sub-techs: reclaimPolicy, static NFS PV, NFS CSI driver, PV immutability,
           Flux prune + protection finalizers
Environment: DEV & Prod k8s clusters | NFS server 10.0.40.120
Discovered during: Testing PVC deletion and recreation workflow
Related: TS-K8S-005 (StorageClass immutability — next failure in migration chain),
         TS-K8S-006 (complete NFS storage guide),
         TS-K8S-026 (released PV cleanup — orphaned PVs from Retain policy)
Re-opened: No

_____________________________________________________________________

[Issue Description]
I had a static NFS PV (`nfs-testing`) with `reclaimPolicy: Delete`, thinking
that deleting the PVC would clean up test data on the NAS automatically. Instead,
the PV got stuck in `Failed` state and the NFS data was completely untouched.

```yaml
# pv.yaml (original)
spec:
  persistentVolumeReclaimPolicy: Delete
  nfs:
    server: 10.0.40.120
    path: /volume1/k8s-prod/testing
```

After deleting the PVC:
```
kubectl delete pvc testing-storage -n testing
kubectl get pv nfs-testing
# NAME          STATUS   CLAIM                      STORAGECLASS
# nfs-testing   Failed   testing/testing-storage
```

PV stuck in `Failed`, still referencing the deleted PVC. NFS data on the NAS
was not deleted.

_____________________________________________________________________

[Analysis]

# Step 1: PV events — found the error

```
kubectl describe pv nfs-testing
# Events:
#   Warning  VolumeFailedDelete  94s   persistentvolume-controller
#     error getting deleter volume plugin for volume "nfs-testing":
#     no deletable volume plugin matched
```

K8s tried to call a delete plugin but none exists for static NFS volumes.

# Step 2: Understanding what reclaimPolicy actually does

The name is misleading — it doesn't fire when you delete the PV. It fires when
the PVC unbinds (i.e., PVC is deleted or released). "Reclaim" means "what to do
with the PV when it gets reclaimed from a claim."

With `Delete` set, the chain is:
1. PVC deleted → K8s sees PV is now unclaimed
2. Triggers reclaim → looks for a volume delete plugin matching the PV source
3. No NFS CSI driver installed → `no deletable volume plugin matched` → `Failed`
4. PV stuck: still holds old `claimRef`, status `Failed`, cannot rebind

NFS data on the NAS was completely untouched — the `Failed` state is just a
provisioner call failure.

# Step 3: What happens to NAS when a static PV is deleted

I tested this — manually deleting a static PV (`kubectl delete pv`) just removes
the PV object from the cluster. The NAS directory is never touched, regardless of
reclaimPolicy:

```
kubectl delete pv nfs-testing
  └─► PV object removed from cluster
        └─► NAS directory /volume1/k8s-prod/testing: UNTOUCHED
              └─► must be deleted manually on the NAS
```

Only the NFS CSI driver with `reclaimPolicy: Delete` on a dynamically provisioned
PV can actually delete the NAS subdirectory. Static PVs never get automatic NAS
cleanup — see TS-K8S-026 for how this causes orphaned directories to accumulate.

# Step 4: PVC binding behavior

I confirmed through CLI testing:

If no `storageClassName` is set on a PVC:
- If a default StorageClass exists → K8s binds using that class + `accessModes` + `capacity`
- If no default StorageClass exists (my lab) → PVC only binds to PVs that also
  have no `storageClassName` set

```
kubectl get storageclass
# No (default) annotation present → no default StorageClass in cluster
```

Also confirmed: a PVC that is already bound cannot be re-evaluated. `kubectl apply`
on a bound PVC only patches annotations — must delete and recreate to test new
binding behavior.

# Step 5: PV immutability discovery

While trying to fix by editing the PV:
```
kubectl apply -f pv.yaml   # with modified nfs.path
# Error: spec.persistentVolumeSource is immutable after creation
```

Fields immutable after PV creation: `nfs.path`, `nfs.server`, `capacity`,
`accessModes`, `volumeMode`.

Fields mutable on a live PV: `persistentVolumeReclaimPolicy` (can be patched
in-place), `claimRef` (can be patched to null to recover a stuck PV).

# Step 6: Recovering a stuck PV

```
kubectl patch pv nfs-testing -p '{"spec":{"claimRef": null}}'
kubectl get pv nfs-testing
# STATUS: Available
```

# Step 7: Pod ↔ storage relationship clarification

I confirmed through testing:
- Pod deleted → nothing happens to PVC, PV, or NFS data
- Deployment deleted → nothing happens to PVC, PV, or NFS data
- Pod does not create a folder named after itself — any folder on NAS was created
  by the application running inside the pod
- NFS mount is a direct mount of the full path, not per-pod subdirectory like Docker
- Data lifecycle is controlled entirely by PVC/PV, not pod or deployment lifecycle

_____________________________________________________________________

[Final Root Cause]
`reclaimPolicy: Delete` was set on a static NFS PV without an NFS CSI provisioner
installed. When the PVC was deleted, K8s attempted to call a delete plugin that
didn't exist, causing the PV to enter `Failed` state with `no deletable volume
plugin matched`.

_____________________________________________________________________

[Final Solution]

# Fix: install NFS CSI driver and migrate to dynamic provisioning

Installing `nfs.csi.k8s.io` registers a volume plugin. With it present:
- `reclaimPolicy: Delete` calls the CSI driver → actually deletes the NFS subdirectory
- Dynamic provisioning works — no need to pre-create static PVs per workload

Files changed (both dev + prod):

`nfs-csi-driver.yaml` — installs the driver via Flux:
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

`storageclass.yaml` — enables dynamic provisioning:
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

`pvc.yaml` — migrated from static to dynamic:
```yaml
# Before (static binding to named PV):
spec:
  volumeName: nfs-testing

# After (dynamic via StorageClass):
spec:
  storageClassName: nfs-csi-testing
```

`pv.yaml` — static `nfs-testing` PV removed (CSI driver creates PVs automatically
per PVC).

# Why manual steps were required with Flux

Flux with `prune: true` tries to delete the old static PV once removed from git,
but it hangs in `Terminating` forever due to K8s protection finalizers:

- `kubernetes.io/pvc-protection` — blocks PVC deletion while a pod is mounting it
- `kubernetes.io/pv-protection` — blocks PV deletion while a PVC is bound to it

Flux cannot override these. It retries indefinitely and blocks reconciliation of
the new dynamic resources.

Correct migration order before pushing git changes:
```
# 1. Delete pods using the PVC (removes pvc-protection finalizer blocker)
kubectl delete pods -n testing --all

# 2. Delete the PVC (removes pv-protection finalizer blocker)
kubectl delete pvc testing-storage -n testing

# 3. Delete the static PV manually
kubectl delete pv nfs-testing

# 4. Push git changes — Flux reconciles → StorageClass created →
#    dynamic PVC created → CSI driver provisions PV + NFS subdirectory
```

Skipping step 1 → PVC stuck in `Terminating` → PV stuck in `Terminating` → Flux
reconciliation blocked entirely.

# Workaround for static NFS PVs (without CSI)

For static NFS PVs where you don't want CSI, change policy to `Retain`:
```
kubectl patch pv nfs-testing -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```
Then manually clear `claimRef` when ready to reuse.

Verified: Yes — dynamic provisioning working, PVC deletion properly deletes NFS
subdirectory via CSI driver, no more `Failed` PV states.

_____________________________________________________________________

[Risk Level] MEDIUM

Static to dynamic migration requires manual cleanup before git push; brief
storage unavailability during migration. Skipping the manual steps blocks Flux
reconciliation entirely.

_____________________________________________________________________

[References]
- TS-K8S-005 — StorageClass immutability (next failure in the migration chain)
- TS-K8S-006 — complete NFS storage guide (final architecture from this journey)
- TS-K8S-026 — released PV cleanup (orphaned PVs from Retain policy)
