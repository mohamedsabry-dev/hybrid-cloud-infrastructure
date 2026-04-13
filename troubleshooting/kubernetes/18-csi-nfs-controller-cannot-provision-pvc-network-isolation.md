# TS-K8S-018 | 2026-04-08 | RESOLVED

## 1. Context

- **System:** CSI NFS Driver / PVC Provisioning / Network Architecture
- **Environment:** k8s-dev cluster
- **Related Components:** CSI NFS controller, StorageClass, PVC provisioning, network segmentation
- **Discovered During:** Loki StatefulSet deployment
- **Related Cases:**
  - TS-K8S-006 — Complete NFS storage guide (architecture reference)
  - TS-K8S-015 — Stale NFS mount on CSI restart (companion case — both involve CSI deployment decisions causing storage failures)

---

## 2. Issue

**Symptom:** New PVCs stuck in `Pending`. Loki StatefulSet could not start because PVC provisioning failed with mount timeouts.

```bash
kubectl get pvc -A
# monitoring   storage-loki-0    Pending   nfs-retain   35m
# default      test-pvc          Pending   nfs-retain   2m
```

**Existing PVCs (Grafana, Prometheus, MariaDB) were Bound** — only new provisioning failed.

**CSI Controller Logs — Mount Timeout:**
```
I0408 18:10:30 controllerserver.go:509 internally mounting 10.0.40.120:/volume1/k8s-dev at /tmp/pvc-xxx
I0408 18:10:30 mount_linux.go:270 Mounting cmd (mount) with arguments (-t nfs ...)
E0408 18:12:20 utils.go:116 GRPC error: rpc error: code = Internal desc = failed to mount nfs server:
  mount volume 10.0.40.120:/volume1/k8s-dev to /tmp/pvc-xxx timeout after 110s
```

**Impact:** New PVC provisioning completely blocked. Loki cannot start.

---

## 3. Analysis

### Step 1: Check CSI Controller Location

```bash
kubectl get pods -n kube-system -o wide | grep csi-nfs-controller
# csi-nfs-controller-xxx   5/5   Running   10.0.61.11   k8s-master2.lab.local
# csi-nfs-controller-xxx   5/5   Running   10.0.61.10   k8s-master1.lab.local
```

**Problem:** Controllers on masters (10.0.61.x), NFS on 10.0.40.x — no network route between them.

### Step 2: Test Network from Master to NFS

```bash
# From master node
ping -c 2 10.0.40.120   # No reply
nc -zv 10.0.40.120 2049  # Connection refused / timeout
```

Finding: Masters have no route to storage network.

### Step 3: Compare with Prod Cluster (Working)

```bash
kubectl get pods -n kube-system -o wide | grep csi-nfs-controller
# prod: controllers on workers — provisioning works
```

### Network Architecture

| Node Type | Primary Network | Storage Network | NFS Access |
|-----------|-----------------|-----------------|------------|
| Masters | 10.0.61.x | None | No |
| Workers | 10.0.64.x | 10.0.40.20x (dedicated NIC) | Yes |
| NFS Server | — | 10.0.40.120 | — |

### Why Existing PVCs Were Still Bound

The CSI controller is only needed for **create and delete operations**. Existing mounts are managed by csi-nfs-node on each worker node. Once a PVC is provisioned and a pod is running, the controller is not involved — the mount persists independently.

### Why Default Tolerations Allowed Scheduling on Masters

The CSI NFS Helm chart includes default tolerations for `control-plane`, allowing controller pods to schedule on masters without any explicit configuration. Without explicit node affinity, the scheduler placed them on masters.

---

## 4. Root Cause

CSI NFS controller pods scheduled on master nodes (10.0.61.x) which have no network route to the NFS storage server (10.0.40.120). The controller temporarily mounts NFS during PVC provisioning to create subdirectories — this mount attempt timed out after 110 seconds.

---

## 5. Solution

### Add Node Affinity to CSI Controller

```yaml
# HelmRelease values
controller:
  replicas: 2
  priorityClassName: system-cluster-critical
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: node-role.kubernetes.io/control-plane
                operator: DoesNotExist   # DoesNotExist = workers only
```

### ⚠️ DoesNotExist vs Exists — Critical Distinction

| Operator | Meaning | Targets |
|---|---|---|
| `DoesNotExist` on control-plane label | Schedule on nodes WITHOUT the label | Workers only |
| `Exists` on control-plane label | Schedule on nodes WITH the label | Masters only |

**Always verify actual placement after applying:**
```bash
kubectl get pods -n kube-system -o wide | grep csi-nfs-controller
# Must show worker IPs (10.0.64.x), not master IPs (10.0.61.x)
```

### Additional Fixes Applied

**NFSv3 with nolock (StorageClass):**

To avoid NFSv4 state recovery issues on the NAS:

```yaml
mountOptions:
  - nfsvers=3
  - nolock
  - soft
  - timeo=30
  - retrans=3
```

**ASUSTOR NFS Recovery Directory:**
```bash
mkdir -p /var/lib/nfs/v4recovery
chmod 755 /var/lib/nfs/v4recovery
```

### Apply and Verify

```bash
flux reconcile helmrelease csi-driver-nfs -n kube-system --with-source

kubectl get pods -n kube-system -o wide | grep csi-nfs-controller
# Should now show worker nodes

# Test new PVC provisioning
kubectl apply -f test-pvc.yaml
kubectl get pvc test-pvc -w
# Should go to Bound quickly
```

---

## 6. Architecture Decision: Controllers on Workers

| Approach | Pros | Cons |
|----------|------|------|
| **Controllers on workers (chosen)** | Matches network — workers have NFS access | Controllers share resources with workloads; if all workers down, no provisioning |
| Controllers on masters | Dedicated resources, isolated | Requires routing masters to storage network — expanded attack surface |

**Decision:** Controllers on workers — matches the network architecture where only workers have storage access. No firewall changes needed.

### Known Limitation

If all worker nodes are simultaneously down, CSI controller cannot provision or delete PVCs. Existing pod mounts are unaffected (handled by csi-nfs-node, but those are also down if workers are down). This is an acceptable tradeoff for the network isolation design.

---

## 7. Solution Risk

- **Risk Level:** Low
- Controllers moving from masters to workers: Brief provisioning unavailability during rollout
- NFSv3 downgrade: Avoids NFSv4 state recovery issues on ASUSTOR NAS

---

## 8. Impact After Fix

- CSI controllers running on worker nodes
- New PVC provisioning working immediately
- Loki StatefulSet started successfully
- Existing PVCs remain bound and functional

---

## 9. Notes

### Lessons Learned

1. **CSI controller needs network access to NFS storage** — It temporarily mounts NFS to create subdirectories during provisioning
2. **Default tolerations cause unexpected placement** — CSI NFS chart tolerates control-plane by default; must add explicit affinity in network-segmented environments
3. **Existing PVCs work ≠ new provisioning works** — Controller is only needed for create/delete, not ongoing mounts
4. **Verify controller placement after every CSI update** — A Flux change could reschedule controllers if affinity is not explicitly configured
5. **DoesNotExist ≠ Exists** — Easy to invert. Always verify with `kubectl get pods -o wide`
6. **Test PVC provisioning after any infrastructure change** — `kubectl apply -f test-pvc.yaml && kubectl get pvc -w`

### Commands Reference

```bash
# Check CSI controller location
kubectl get pods -n kube-system -o wide | grep csi-nfs-controller

# Test network from master to NFS
ping -c 2 10.0.40.120
nc -zv 10.0.40.120 2049

# Verify StorageClass mount options
kubectl get storageclass nfs-retain -o yaml | grep -A10 mountOptions

# Check PVC events
kubectl describe pvc <n> -n <namespace> | tail -20

# Check CSI controller logs
kubectl logs -n kube-system <csi-nfs-controller-pod> -c nfs
```

---

## 10. Workaround

**If controllers stuck on masters and PVC provisioning fails:**

**Option A: Move controllers to workers (permanent fix)**
Add nodeAffinity with DoesNotExist on control-plane label as shown above.

**Option B: Manually create static PV (temporary)**
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: manual-pv-loki
spec:
  capacity:
    storage: 10Gi
  accessModes: [ReadWriteOnce]
  nfs:
    server: 10.0.40.120
    path: /volume1/k8s-dev/manual-loki
  storageClassName: nfs-retain
```

Create the NAS directory manually, create the PV, create PVC with `spec.volumeName: manual-pv-loki`. This is a workaround only — fix controller placement for proper dynamic provisioning.