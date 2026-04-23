# TS-K8S-005 | 2026-04-01 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / NFS CSI Storage / FluxCD
Sub-techs: StorageClass, PVC, NFS CSI driver, Flux Kustomization,
           StorageClass immutability, infeasible provisioning cache
Environment: DEV k8s cluster | NFS server 10.0.40.120
Discovered during: Migration from static NFS PV to dynamic CSI provisioning (TS-K8S-004)
Related: TS-K8S-004 (NFS PV reclaimPolicy — CSI driver migration),
         TS-K8S-006 (complete NFS storage guide)
Re-opened: No

_____________________________________________________________________

[Issue Description]
After migrating `testing-storage` from a static NFS PV to dynamic NFS CSI
provisioning (TS-K8S-004), I created the new StorageClass with an invalid
parameter (`onDeletePolicy`). This caused a chain of three compounding failures:

1. PVC stuck in `Pending` — provisioner rejected the StorageClass parameter
2. Flux stuck on old git revision — StorageClass `parameters` are immutable,
   dry-run kept failing
3. PVC stuck even after StorageClass was fixed — infeasible error cached by
   provisioner, retries blocked indefinitely

Provisioner error:
```
Warning  ProvisioningFailed  nfs.csi.k8s.io_k8s-worker3.lab.local_...
  rpc error: code = InvalidArgument desc = invalid parameter "onDeletePolicy" in storage class
```

Flux dry-run error:
```
NAME         REVISION               READY   MESSAGE
deployments  dev@sha1:c4c1b48e      False   StorageClass/nfs-csi-testing dry-run failed (Invalid):
             StorageClass.storage.k8s.io "nfs-csi-testing" is invalid:
             parameters: Forbidden: updates to parameters are forbidden.
```

PVC error after StorageClass fix:
```
Warning  ProvisioningFailed  storageclass.storage.k8s.io "nfs-csi-testing" not found
Normal   ExternalProvisioning  Waiting for a volume to be created...
```

_____________________________________________________________________

[Analysis]

# Failure 1: Invalid StorageClass parameter

The `storageclass.yaml` had `onDeletePolicy: delete` under `parameters`:

```yaml
parameters:
  server: "10.0.40.120"
  share: "/volume1/k8s-dev/testing"
  onDeletePolicy: delete        # ← NOT a valid NFS CSI driver parameter
```

`onDeletePolicy` doesn't exist in the NFS CSI driver's parameter set. The
`reclaimPolicy: Delete` field on the StorageClass itself handles cleanup — no
extra parameter needed.

The provisioner rejected it immediately and flagged the error as **infeasible**,
meaning it won't retry automatically. Retries delayed indefinitely.

# Failure 2: Flux stuck on old revision (StorageClass immutability)

After I fixed the YAML in git (removed `onDeletePolicy`) and pushed, Flux didn't
pick up the new revision. The `deployments` kustomization stayed stuck on the old
SHA.

Why: StorageClass `parameters` are immutable after creation in K8s. Flux does a
dry-run before applying — the dry-run tried to update the existing StorageClass to
remove `onDeletePolicy`. K8s rejected it. Since the dry-run failed, Flux never
advanced to the new revision.

Same immutability pattern as `spec.persistentVolumeSource` on PVs (TS-K8S-004).
Immutable StorageClass fields: `parameters`, `provisioner`, `volumeBindingMode`,
`reclaimPolicy`.

# Failure 3: PVC infeasible cache not cleared by StorageClass fix

After I manually deleted the StorageClass and forced Flux to reconcile the new
revision, the StorageClass was recreated correctly. But the PVC remained `Pending`.

Why: the PVC object itself had the `infeasible` flag cached from the earlier failed
provisioning attempt. K8s marks provisioning attempts that fail with `infeasible`
errors (like `InvalidArgument`) as permanently failed for that PVC — retries are
blocked until the PVC object is recreated.

# Why pods didn't block PVC deletion

The nginx-test pods were in `Pending/FailedScheduling` — they never actually
mounted the PVC. Because the pods never mounted the volume, the `pvc-protection`
finalizer didn't block deletion. The PVC deleted cleanly.

Had the pods been `Running` with the volume mounted, deletion would have hung
until pods were removed first.

_____________________________________________________________________

[Final Root Cause]
Three compounding failures from one bad parameter:

1. `onDeletePolicy: delete` is not a valid NFS CSI driver parameter — provisioner
   rejected it and flagged the PVC as infeasible
2. StorageClass `parameters` are immutable — Flux dry-run failed trying to update,
   so it never advanced to the fixed git revision
3. Infeasible errors are cached on the PVC object — fixing the StorageClass alone
   didn't clear it, the PVC had to be deleted and recreated

The `reclaimPolicy: Delete` field on the StorageClass itself handles cleanup. No
extra parameter needed in `parameters`.

_____________________________________________________________________

[Final Solution]

# Step 1: Fix the StorageClass YAML (remove invalid parameter)

```yaml
# storageclass.yaml — before
parameters:
  server: "10.0.40.120"
  share: "/volume1/k8s-dev/testing"
  onDeletePolicy: delete        # invalid — removed

# storageclass.yaml — after
parameters:
  server: "10.0.40.120"
  share: "/volume1/k8s-dev/testing"
```

# Step 2: Delete the existing StorageClass manually

Flux can't update immutable `parameters` — must delete so it can be recreated:
```
kubectl delete storageclass nfs-csi-testing
```

# Step 3: Force Flux to pick up the new revision

```
flux reconcile kustomization deployments --with-source
# ✔ fetched revision dev@sha1:9c9b2cb3...
# ✔ applied revision dev@sha1:9c9b2cb3...
```

Verified both kustomizations on the same revision:
```
flux get kustomization
# NAME         REVISION              READY   MESSAGE
# deployments  dev@sha1:9c9b2cb3     True    Applied revision: dev@sha1:9c9b2cb3
# flux-system  dev@sha1:9c9b2cb3     True    Applied revision: dev@sha1:9c9b2cb3
```

Note: `flux reconcile --with-source` is required here. Without `--with-source`,
Flux re-applies the current cached revision — it doesn't re-fetch from git. When
stuck on an old revision due to a failed dry-run, `--with-source` is needed to
advance to the newer commit.

# Step 4: Delete the stale PVC to clear the infeasible cache

```
kubectl delete pods -n testing --all
kubectl delete pvc testing-storage -n testing
```

# Step 5: Reconcile Flux to recreate the PVC

```
flux reconcile kustomization deployments
```

# Step 6: Verify PVC bound and pods running

```
kubectl get pvc testing-storage -n testing -w
# NAME              STATUS   VOLUME                                     CAPACITY
# testing-storage   Bound    pvc-3aa5ba61-09ff-41b8-816b-40589d5a9eff   100Gi
```

Verified: Yes — PVC bound to dynamically provisioned PV, StorageClass recreated
with valid parameters, Flux kustomization advanced to new revision, pods scheduled
and running, NFS subdirectory auto-created by CSI driver.

_____________________________________________________________________

[Risk Level] LOW

Temporary PVC unavailability during recreation, but pods were already in
`FailedScheduling` state — no active workloads affected.

_____________________________________________________________________

[References]
- TS-K8S-004 — NFS PV reclaimPolicy (CSI driver migration that led to this)
- TS-K8S-006 — complete NFS storage guide (final architecture)
