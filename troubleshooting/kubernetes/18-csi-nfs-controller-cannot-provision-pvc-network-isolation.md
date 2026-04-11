# TS-K8S-018 | 2026-04-08 | RESOLVED

> **REAL INCIDENT** — This case occurred during an unplanned production failure (Loki deployment blocked by network isolation), not planned DR testing. Documented before DR test phase began.

## 1. Context

- **System:** CSI NFS Driver / PVC Provisioning / Network Architecture
- **Environment:** k8s-dev cluster (bare-metal kubeadm, 3 masters, 3 workers, Calico CNI, NFS CSI storage, ASUSTOR NAS)
- **Related Components:** CSI NFS controller, StorageClass, PVC provisioning, network segmentation
- **Discovered During:** Loki StatefulSet deployment
- **Related:** Case 15 (CSI NFS Restart Stale Mount)

---

## 2. Issue

**Symptom:** New PVCs stuck in `Pending` state. Loki StatefulSet could not start because PVC provisioning failed with mount timeouts.

**PVC Stuck in Pending:**
```bash
kubectl get pvc -A
```
```
NAMESPACE    NAME              STATUS    STORAGECLASS   AGE
monitoring   storage-loki-0    Pending   nfs-retain     35m
default      test-pvc          Pending   nfs-retain     2m
```

Existing PVCs (Grafana, Prometheus, MariaDB) were Bound - only new provisioning failed.

**Pod Pending Due to Unbound PVC:**
```bash
kubectl describe pod loki-0 -n monitoring
```
```
Events:
  Warning  FailedScheduling  default-scheduler  0/6 nodes are available: pod has unbound immediate PersistentVolumeClaims
```

**CSI Controller Logs - Mount Timeout:**
```bash
kubectl logs -n kube-system csi-nfs-controller-xxx -c nfs
```
```
I0408 18:10:30.476564       1 controllerserver.go:509] internally mounting 10.0.40.120:/volume1/k8s-dev at /tmp/pvc-xxx
I0408 18:10:30.486034       1 mount_linux.go:270] Mounting cmd (mount) with arguments (-t nfs -o soft,timeo=30,retrans=3 10.0.40.120:/volume1/k8s-dev /tmp/pvc-xxx)
E0408 18:12:20.486007       1 utils.go:116] GRPC error: rpc error: code = Internal desc = failed to mount nfs server: mount volume 10.0.40.120:/volume1/k8s-dev to /tmp/pvc-xxx timeout after 110s
```

**Impact:**
- New PVC provisioning completely blocked
- Loki StatefulSet cannot start
- Any new workloads requiring NFS storage cannot deploy

---

## 3. Analysis

### Step 1: Check CSI Controller Location

```bash
kubectl get pods -n kube-system -o wide | grep csi-nfs-controller
```
```
csi-nfs-controller-xxx   5/5   Running   10.0.61.11   k8s-master2.lab.local
csi-nfs-controller-xxx   5/5   Running   10.0.61.10   k8s-master1.lab.local
```

**Problem:** Controllers on masters (10.0.61.x), NFS on 10.0.40.x - no route.

### Step 2: Workers Showing NFS Lock Issues

```bash
# On worker nodes
dmesg | grep -i nfs
```
```
NFS: 10.0.40.120: lost 2 locks
NFS: 10.0.40.120: lost 1 locks
```

### Step 3: ASUSTOR NFS Recovery Failure

```bash
# On ASUSTOR NAS
dmesg | tail -30
```
```
NFSD: unable to find recovery directory /var/lib/nfs/v4recovery
NFSD: Unable to initialize client recovery tracking! (-2)
NFSD: starting 90-second grace period
```

### Step 4: Test Network from Master to NFS

```bash
# From master node
ping -c 2 10.0.40.120
nc -zv 10.0.40.120 2049
```

**Result:** No connectivity - masters have no route to storage network.

### Step 5: Compare with Prod Cluster

```bash
# On prod - controllers on workers (working)
kubectl get pods -n kube-system -o wide | grep csi-nfs-controller
```

**Finding:** Prod has controllers on workers where storage network is accessible.

### Network Architecture

| Node Type | Primary Network | Storage Network | NFS Access |
|-----------|-----------------|-----------------|------------|
| Masters   | 10.0.61.x       | None            | No         |
| Workers   | 10.0.64.x       | 10.0.40.20x     | Yes        |
| NFS Server| -               | 10.0.40.120     | -          |

CSI controller needs to mount NFS temporarily during provisioning to create subdirectories. If controller runs on masters without storage network access, provisioning fails.

---

## 4. Root Cause

CSI NFS controller pods were running on master nodes (10.0.61.x) which have no network connectivity to the NFS storage server (10.0.40.120). Workers have dedicated storage NICs on 10.0.40.x network.

The CSI NFS Helm chart includes **default tolerations** for control-plane, allowing controllers to schedule on masters without explicit configuration.

**Why It Worked Before:**
- Existing PVCs (Grafana, Prometheus, MariaDB) were provisioned when:
  - Controllers may have been scheduled on workers by chance
  - Or network routing was temporarily available
  - Or PVs were created during initial setup with different conditions

---

## 5. Solution

### Add Node Affinity to CSI Controller

**File:** `kubernetes/dev/deployments/infrastructure/storage/nfs-csi-driver.yaml`

```yaml
spec:
  values:
    controller:
      replicas: 2
      priorityClassName: system-cluster-critical
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: node-role.kubernetes.io/control-plane
                    operator: DoesNotExist
    node:
      priorityClassName: system-node-critical
```

### Apply and Verify

```bash
# Apply changes
flux reconcile helmrelease csi-driver-nfs -n kube-system --with-source

# Verify controllers moved to workers
kubectl get pods -n kube-system -o wide | grep csi-nfs-controller

# Test PVC provisioning
kubectl get pvc test-nfs-delete
```

### Additional Fixes Applied

**NFSv3 with nolock (StorageClass):**

To avoid NFSv4 state recovery issues and rpc.statd requirements:

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
# On ASUSTOR
mkdir -p /var/lib/nfs/v4recovery
chmod 755 /var/lib/nfs/v4recovery
```

### Files Changed

- `kubernetes/dev/deployments/infrastructure/storage/nfs-csi-driver.yaml`
- `kubernetes/prod/deployments/infrastructure/storage/nfs-csi-driver.yaml`
- `kubernetes/dev/deployments/infrastructure/storage/storageclass.yaml` (NFSv3 + nolock)

### Prevention Measures

1. Always verify CSI controller placement matches storage network access
2. Explicitly configure node affinity for CSI controllers in network-segmented environments
3. Document network architecture (which nodes can access which storage)
4. Test PVC provisioning after cluster changes/reboots

---

## 6. Solution Risk

- **Risk Level:** Low
- **Potential Impact:**
  - Controllers moving from masters to workers: Brief provisioning unavailability during rollout
  - NFSv3 downgrade: Potential feature loss vs NFSv4 (but avoids state recovery issues)
  - Controllers share resources with workloads on workers

### Architecture Options Comparison

| Approach | Pros | Cons |
|----------|------|------|
| **Controllers on workers** | No network changes, masters isolated, simple | Controllers share resources with workloads |
| **Open masters to storage** | Standard architecture, dedicated controller resources | Firewall changes, expanded attack surface |

**Decision:** Controllers on workers - matches network architecture where only workers have storage access.

---

## 7. Impact After Fix

**Observed Results:**
- CSI controllers running on worker nodes
- New PVC provisioning working immediately
- Loki StatefulSet started successfully
- Existing PVCs remain bound and functional

---

## 8. Notes

### Lessons Learned

1. **CSI controller needs network access to storage** - It temporarily mounts NFS to create subdirectories during provisioning
2. **Default tolerations can cause unexpected placement** - CSI NFS chart tolerates control-plane by default
3. **Test PVC provisioning after infrastructure changes** - Existing PVCs work ≠ new provisioning works
4. **Document network architecture** - Which nodes have access to which networks

### Commands Reference

#### Check CSI Controller Location
```bash
kubectl get pods -n kube-system -o wide | grep csi-nfs-controller
```

#### Verify StorageClass Mount Options
```bash
kubectl get storageclass nfs-retain -o yaml | grep -A10 mountOptions
```

#### Check PVC Events
```bash
kubectl describe pvc <name> -n <namespace> | tail -20
```

#### Test Network from Master to NFS
```bash
# From master node
ping -c 2 10.0.40.120
nc -zv 10.0.40.120 2049
```

#### Check CSI Controller Logs
```bash
kubectl logs -n kube-system <csi-nfs-controller-pod> -c nfs
```

### Related Files

- `kubernetes/dev/deployments/infrastructure/storage/nfs-csi-driver.yaml`
- `kubernetes/prod/deployments/infrastructure/storage/nfs-csi-driver.yaml`
- `kubernetes/dev/deployments/infrastructure/storage/storageclass.yaml`

---

## 9. Workaround

**If controllers are stuck on masters and PVC provisioning fails:**

**Option A: Move controllers to workers (permanent fix)**
Add nodeAffinity to HelmRelease values as shown in Solution section.

**Option B: Manually create PV (temporary)**
If urgent PVC needed before controller fix:
1. Manually create subdirectory on NFS server
2. Create static PV pointing to subdirectory
3. Bind PVC to static PV

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: manual-pv-loki
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  nfs:
    server: 10.0.40.120
    path: /volume1/k8s-dev/manual-loki
  storageClassName: nfs-retain
```

**Note:** Manual PV approach is a workaround only. Fix controller placement for proper dynamic provisioning.
