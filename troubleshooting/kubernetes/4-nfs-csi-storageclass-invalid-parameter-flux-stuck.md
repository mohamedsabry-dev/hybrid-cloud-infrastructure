# TS-65: NFS CSI StorageClass Invalid Parameter — Flux Stuck on Old Revision + PVC Infeasible Cache

## Status: RESOLVED
## Date: 2026-04-01
## Severity: Medium
## Environment: k8s-dev cluster
## Related: TS-64 (NFS PV reclaimPolicy — CSI driver migration)

---

## 1. Issue Summary

After migrating `testing-storage` from a static NFS PV to dynamic NFS CSI provisioning (TS-64), the new `StorageClass/nfs-csi-testing` was created with an invalid parameter (`onDeletePolicy`). This caused a chain of three compounding failures:

1. PVC stuck in `Pending` — provisioner rejected the StorageClass parameter
2. Flux stuck on old git revision — StorageClass `parameters` are immutable, dry-run kept failing
3. PVC stuck even after StorageClass was fixed — infeasible error cached by provisioner, retries blocked indefinitely

---

## 2. Root Cause Chain

### Failure 1: Invalid StorageClass Parameter

The `storageclass.yaml` was created with `onDeletePolicy: delete` under `parameters`:

```yaml
parameters:
  server: "10.0.40.120"
  share: "/volume1/k8s-dev/testing"
  onDeletePolicy: delete        # ← NOT a valid NFS CSI driver parameter
```

`onDeletePolicy` does not exist in the NFS CSI driver's parameter set. The `reclaimPolicy: Delete` field on the StorageClass itself handles cleanup — no extra parameter needed.

The provisioner rejected it immediately:

```
Warning  ProvisioningFailed  nfs.csi.k8s.io_k8s-worker3.lab.local_...
  rpc error: code = InvalidArgument desc = invalid parameter "onDeletePolicy" in storage class
```

The error was flagged as **infeasible** — meaning the provisioner will not retry automatically. Retries are delayed indefinitely.

---

### Failure 2: Flux Stuck on Old Revision

After fixing `storageclass.yaml` in git (removing `onDeletePolicy`) and pushing, Flux did not pick up the new revision automatically. The `deployments` kustomization remained stuck on the old SHA:

```
NAME         REVISION               READY   MESSAGE
deployments  dev@sha1:c4c1b48e      False   StorageClass/nfs-csi-testing dry-run failed (Invalid):
             StorageClass.storage.k8s.io "nfs-csi-testing" is invalid:
             parameters: Forbidden: updates to parameters are forbidden.
```

**Why:** StorageClass `parameters` are **immutable after creation** in Kubernetes. Flux performs a dry-run before applying — the dry-run detected the existing StorageClass and tried to update it to remove `onDeletePolicy`. Kubernetes rejected it. Since the dry-run failed, Flux never advanced to the new revision.

This is a Kubernetes immutability rule — same as `spec.persistentVolumeSource` on PVs. Fields that are immutable:
- `StorageClass.parameters`
- `StorageClass.provisioner`
- `StorageClass.volumeBindingMode`
- `StorageClass.reclaimPolicy`

---

### Failure 3: PVC Infeasible Cache Not Cleared by StorageClass Fix

After manually deleting the StorageClass (`kubectl delete storageclass nfs-csi-testing`) and forcing Flux to reconcile the new revision, the StorageClass was recreated correctly. However the PVC remained in `Pending`:

```
Warning  ProvisioningFailed  storageclass.storage.k8s.io "nfs-csi-testing" not found
Normal   ExternalProvisioning  Waiting for a volume to be created...
```

**Why:** The PVC object itself had the `infeasible` flag cached from the earlier failed provisioning attempt. Kubernetes marks provisioning attempts that fail with `infeasible` errors (like `InvalidArgument`) as permanently failed for that PVC — retries are blocked until the PVC object is recreated. Deleting and recreating the StorageClass does not clear this flag.

---

## 3. Full Resolution — Step by Step

### Step 1: Fix the StorageClass YAML (remove invalid parameter)

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

Push to git. `reclaimPolicy: Delete` on the StorageClass is sufficient — the CSI driver deletes the provisioned subdirectory on the NFS share when the PVC is deleted.

---

### Step 2: Delete the existing StorageClass manually

Flux cannot update immutable `parameters` — must delete the object so it can be recreated:

```bash
kubectl delete storageclass nfs-csi-testing
# storageclass.storage.k8s.io "nfs-csi-testing" deleted
```

---

### Step 3: Force Flux to pick up the new revision

Even after the git fix and manual StorageClass deletion, Flux remained stuck on the old revision. The `--with-source` flag forces the GitRepository to re-fetch before reconciling:

```bash
flux reconcile kustomization deployments --with-source
# ✔ fetched revision dev@sha1:9c9b2cb3...
# ✔ applied revision dev@sha1:9c9b2cb3...
```

Verify both kustomizations are on the same revision and healthy:

```bash
flux get kustomization
# NAME         REVISION              READY   MESSAGE
# deployments  dev@sha1:9c9b2cb3     True    Applied revision: dev@sha1:9c9b2cb3
# flux-system  dev@sha1:9c9b2cb3     True    Applied revision: dev@sha1:9c9b2cb3
```

---

### Step 4: Delete the stale PVC to clear the infeasible cache

StorageClass was now correct and present, but PVC remained `Pending` due to cached infeasible state. Pods must be deleted first to release the `pvc-protection` finalizer:

```bash
# Delete pods to release pvc-protection finalizer
kubectl delete pods -n testing --all

# Delete the PVC to clear the infeasible provisioning cache
kubectl delete pvc testing-storage -n testing
```

---

### Step 5: Reconcile Flux to recreate the PVC

```bash
flux reconcile kustomization deployments
# ✔ applied revision dev@sha1:9c9b2cb3...
```

---

### Step 6: Verify PVC bound and pods running

```bash
kubectl get pvc testing-storage -n testing -w
# NAME              STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
# testing-storage   Bound    pvc-3aa5ba61-09ff-41b8-816b-40589d5a9eff   100Gi      RWX            nfs-csi-testing
```

PVC is `Bound`. The CSI driver dynamically provisioned a PV (`pvc-3aa5ba61-...`) and created a subdirectory on the NFS share. Pods scheduled and running.

---

## 4. Why `flux reconcile --with-source` vs Without

| Command | What it does |
|---|---|
| `flux reconcile kustomization deployments` | Re-applies current cached git revision — does NOT re-fetch from git |
| `flux reconcile kustomization deployments --with-source` | Forces GitRepository to re-fetch from remote first, then reconciles with latest commit |

When Flux is stuck on an old revision due to a failed dry-run, `--with-source` is required to advance to a newer commit. Without it, Flux keeps retrying the same failed revision.

---

## 5. Why Pods Were Not Blocking PVC Deletion This Time

The nginx-test pods were showing as `Used By` in PVC describe, but they were in a `Pending/FailedScheduling` state — they had never actually mounted the PVC (scheduling failed). Because the pods never mounted the volume, the `pvc-protection` finalizer did not block deletion. The PVC deleted cleanly.

Had the pods been `Running` with the volume mounted, deletion would have hung until pods were removed first.

---

## 6. Key Takeaways

| Rule | Detail |
|---|---|
| `StorageClass.parameters` are immutable | Cannot update after creation — must delete + recreate |
| `onDeletePolicy` is NOT a valid NFS CSI parameter | Use `reclaimPolicy: Delete` on the StorageClass itself |
| Infeasible provisioning errors are cached on the PVC | Fixing the StorageClass is not enough — PVC must be deleted + recreated |
| `flux reconcile --with-source` required when stuck on old revision | Without it, Flux retries the same failed SHA |
| Pods in `Pending/FailedScheduling` do not block PVC deletion | Only `Running` pods with mounted volumes trigger `pvc-protection` finalizer |
| CSI dynamic PV name is auto-generated | `pvc-<uuid>` — not user-defined like static PVs |
