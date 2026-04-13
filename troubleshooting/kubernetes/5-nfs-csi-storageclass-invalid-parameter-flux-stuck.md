# TS-K8S-005 | 2026-04-01 | RESOLVED

## 1. Context

| Attribute | Value |
|-----------|-------|
| **System** | Kubernetes NFS CSI Storage with Flux GitOps |
| **Environment** | k8s-dev cluster |
| **Severity** | Medium |
| **Related Components** | StorageClass, PVC, NFS CSI Driver, Flux Kustomization |
| **Discovered During** | Migration from static NFS PV to dynamic NFS CSI provisioning (TS-K8S-004) |
| **Related Cases** | TS-K8S-004 (NFS PV reclaimPolicy — CSI driver migration), TS-K8S-006 (Complete NFS Storage Guide) |

---

## 2. Issue

### Symptom

After migrating `testing-storage` from a static NFS PV to dynamic NFS CSI provisioning (TS-K8S-004), the new `StorageClass/nfs-csi-testing` was created with an invalid parameter (`onDeletePolicy`). This caused a chain of three compounding failures:

1. PVC stuck in `Pending` — provisioner rejected the StorageClass parameter
2. Flux stuck on old git revision — StorageClass `parameters` are immutable, dry-run kept failing
3. PVC stuck even after StorageClass was fixed — infeasible error cached by provisioner, retries blocked indefinitely

### Error Messages

**Provisioner error:**
```
Warning  ProvisioningFailed  nfs.csi.k8s.io_k8s-worker3.lab.local_...
  rpc error: code = InvalidArgument desc = invalid parameter "onDeletePolicy" in storage class
```

**Flux dry-run error:**
```
NAME         REVISION               READY   MESSAGE
deployments  dev@sha1:c4c1b48e      False   StorageClass/nfs-csi-testing dry-run failed (Invalid):
             StorageClass.storage.k8s.io "nfs-csi-testing" is invalid:
             parameters: Forbidden: updates to parameters are forbidden.
```

**PVC error after StorageClass fix:**
```
Warning  ProvisioningFailed  storageclass.storage.k8s.io "nfs-csi-testing" not found
Normal   ExternalProvisioning  Waiting for a volume to be created...
```

### Impact

- PVC unable to bind — pods could not schedule
- Flux GitOps pipeline blocked on old revision
- Manual intervention required to break the failure chain

---

## 3. Analysis

### Failure 1: Invalid StorageClass Parameter

The `storageclass.yaml` was created with `onDeletePolicy: delete` under `parameters`:

```yaml
parameters:
  server: "10.0.40.120"
  share: "/volume1/k8s-dev/testing"
  onDeletePolicy: delete        # ← NOT a valid NFS CSI driver parameter
```

`onDeletePolicy` does not exist in the NFS CSI driver's parameter set. The `reclaimPolicy: Delete` field on the StorageClass itself handles cleanup — no extra parameter needed.

The provisioner rejected it immediately. The error was flagged as **infeasible** — meaning the provisioner will not retry automatically. Retries are delayed indefinitely.

### Failure 2: Flux Stuck on Old Revision

After fixing `storageclass.yaml` in git (removing `onDeletePolicy`) and pushing, Flux did not pick up the new revision automatically. The `deployments` kustomization remained stuck on the old SHA.

**Why:** StorageClass `parameters` are **immutable after creation** in Kubernetes. Flux performs a dry-run before applying — the dry-run detected the existing StorageClass and tried to update it to remove `onDeletePolicy`. Kubernetes rejected it. Since the dry-run failed, Flux never advanced to the new revision.

This is a Kubernetes immutability rule — same as `spec.persistentVolumeSource` on PVs. Fields that are immutable:
- `StorageClass.parameters`
- `StorageClass.provisioner`
- `StorageClass.volumeBindingMode`
- `StorageClass.reclaimPolicy`

### Failure 3: PVC Infeasible Cache Not Cleared by StorageClass Fix

After manually deleting the StorageClass and forcing Flux to reconcile the new revision, the StorageClass was recreated correctly. However the PVC remained in `Pending`.

**Why:** The PVC object itself had the `infeasible` flag cached from the earlier failed provisioning attempt. Kubernetes marks provisioning attempts that fail with `infeasible` errors (like `InvalidArgument`) as permanently failed for that PVC — retries are blocked until the PVC object is recreated. Deleting and recreating the StorageClass does not clear this flag.

### Why Pods Were Not Blocking PVC Deletion

The nginx-test pods were in a `Pending/FailedScheduling` state — they had never actually mounted the PVC (scheduling failed). Because the pods never mounted the volume, the `pvc-protection` finalizer did not block deletion. The PVC deleted cleanly.

Had the pods been `Running` with the volume mounted, deletion would have hung until pods were removed first.

---

## 4. Root Cause

| Failure | Cause | Detail |
|---------|-------|--------|
| **Failure 1** | Invalid StorageClass Parameter | `onDeletePolicy: delete` is not a valid NFS CSI driver parameter |
| **Failure 2** | StorageClass Immutability | `parameters` cannot be updated after creation — Flux dry-run failed |
| **Failure 3** | PVC Infeasible Cache | Provisioner caches `infeasible` errors on PVC object — fixing StorageClass does not clear it |

The `reclaimPolicy: Delete` field on the StorageClass itself handles cleanup — no extra parameter needed in `parameters`.

---

## 5. Solution

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

### Step 2: Delete the existing StorageClass manually

Flux cannot update immutable `parameters` — must delete the object so it can be recreated:

```bash
kubectl delete storageclass nfs-csi-testing
```

### Step 3: Force Flux to pick up the new revision

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

### Step 4: Delete the stale PVC to clear the infeasible cache

```bash
kubectl delete pods -n testing --all
kubectl delete pvc testing-storage -n testing
```

### Step 5: Reconcile Flux to recreate the PVC

```bash
flux reconcile kustomization deployments
```

### Step 6: Verify PVC bound and pods running

```bash
kubectl get pvc testing-storage -n testing -w
# NAME              STATUS   VOLUME                                     CAPACITY
# testing-storage   Bound    pvc-3aa5ba61-09ff-41b8-816b-40589d5a9eff   100Gi
```

---

## 6. Solution Risk

| Attribute | Value |
|-----------|-------|
| **Risk Level** | Low |
| **Potential Impact** | Temporary PVC unavailability during recreation |
| **Mitigation** | Pods in FailedScheduling state — no active workloads affected |

---

## 7. Impact After Fix

- PVC bound to dynamically provisioned PV
- StorageClass recreated with valid parameters
- Flux Kustomization advanced to new revision
- Pods scheduled and running
- NFS subdirectory auto-created by CSI driver

---

## 8. Notes

### Lessons Learned

| Rule | Detail |
|------|--------|
| `StorageClass.parameters` are immutable | Cannot update after creation — must delete + recreate |
| `onDeletePolicy` is NOT a valid NFS CSI parameter | Use `reclaimPolicy: Delete` on the StorageClass itself |
| Infeasible provisioning errors are cached on the PVC | Fixing the StorageClass is not enough — PVC must be deleted + recreated |
| `flux reconcile --with-source` required when stuck on old revision | Without it, Flux retries the same failed SHA |
| Pods in `Pending/FailedScheduling` do not block PVC deletion | Only `Running` pods with mounted volumes trigger `pvc-protection` finalizer |
| CSI dynamic PV name is auto-generated | `pvc-<uuid>` — not user-defined like static PVs |

### Why `flux reconcile --with-source` vs Without

| Command | What it does |
|---------|--------------|
| `flux reconcile kustomization deployments` | Re-applies current cached git revision — does NOT re-fetch from git |
| `flux reconcile kustomization deployments --with-source` | Forces GitRepository to re-fetch from remote first, then reconciles with latest commit |

When Flux is stuck on an old revision due to a failed dry-run, `--with-source` is required to advance to a newer commit.

### Commands Reference

```bash
# StorageClass Operations
kubectl get sc
kubectl describe sc <name>
kubectl delete sc <name>          # Required for immutable field changes
kubectl get sc <name> -o yaml

# PVC Operations
kubectl get pvc -A
kubectl get pvc -n <namespace>
kubectl describe pvc <name> -n <namespace>   # Shows provisioning errors
kubectl delete pvc <name> -n <namespace>     # Clears infeasible cache
kubectl get pvc <name> -n <namespace> -w

# Flux Operations
flux get kustomizations
flux reconcile kustomization <name>
flux reconcile kustomization <name> --with-source
flux suspend kustomization <name>
flux resume kustomization <name>
flux logs --kind=Kustomization --name=<name>

# Full cleanup sequence for immutable field changes
kubectl delete pods -n <namespace> --all
kubectl delete pvc <name> -n <namespace>
kubectl delete sc <name>
# Push fixed YAML to git
flux reconcile kustomization <name> --with-source
kubectl get sc && kubectl get pvc -n <namespace> && kubectl get pv
```

---

## 9. Workaround

**Temporary (if immediate provisioning needed before proper fix):**

1. Suspend Flux: `flux suspend kustomization deployments`
2. Manually create a corrected StorageClass with a different name
3. Manually create PVC referencing the temporary StorageClass
4. After proper fix in git, delete temporary resources and resume Flux

**Not recommended** — proper fix is straightforward.