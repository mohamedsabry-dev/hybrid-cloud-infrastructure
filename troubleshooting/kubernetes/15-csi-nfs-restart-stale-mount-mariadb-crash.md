# TS-K8S-015 | 2026-04-06 | RESOLVED

## 1. Context

- **System:** CSI NFS Driver, MariaDB StatefulSet
- **Environment:** k8s-dev cluster (bare-metal kubeadm, 3 masters, 3 workers, Calico CNI, NFS CSI storage, Vault sidecar)
- **Related Components:** NFS storage (Synology 10.0.40.120), Flux GitOps, InnoDB
- **Discovered During:** Flux reconciliation of CSI NFS driver configuration changes (priority classes + controller replicas)
- **Related:** Case 3 (NFS Hard Mount Unresponsiveness), Case 6 (Complete NFS Storage Guide)

---

## 2. Issue

**Symptom:** MariaDB entered CrashLoopBackOff with InnoDB I/O errors after Flux reconciled CSI NFS driver configuration changes.

**Error Messages:**
- `InnoDB: Operating system error number 5` - Input/output error (EIO)
- `InnoDB: Error number 5 means 'Input/output error'`
- `InnoDB: File (unknown): 'close' returned OS error 205` - NFS-specific stale handle error

**Timeline of Events:**

| Time | Event |
|------|-------|
| ~19:30 | Flux applied CSI NFS driver changes (priorityClassName + replicas=2) |
| ~19:30 | All csi-nfs-node DaemonSet pods restarted on all nodes |
| ~19:35 | MariaDB on worker1 started failing with I/O errors |
| ~19:40 | MariaDB entered CrashLoopBackOff |
| ~19:50 | Diagnosed as stale NFS mount issue |
| ~19:55 | Cordoned worker1, moved MariaDB to worker2 - WORKING |
| ~20:05 | Rebooted worker1 to clear stale handles |
| ~20:10 | Moved MariaDB back to worker1 - WORKING |

**Pod Status - CrashLoopBackOff:**
```bash
[root@k8s-master1 ~]# kubectl get pods -n database
NAME        READY   STATUS             RESTARTS        AGE
mariadb-0   1/2     CrashLoopBackOff   5 (2m15s ago)   5m11s
```

**MariaDB Container Logs - InnoDB I/O Errors:**
```bash
[root@k8s-master1 ~]# kubectl logs mariadb-0 -n database
2026-04-06 19:40:15 0 [ERROR] InnoDB: Operating system error number 5 in a file operation.
2026-04-06 19:40:15 0 [ERROR] InnoDB: Error number 5 means 'Input/output error'
2026-04-06 19:40:15 0 [ERROR] InnoDB: File (unknown): 'close' returned OS error 205. Cannot continue operation
260406 19:40:15 [ERROR] mysqld got signal 6 ;
```

**Impact:**
- MariaDB database unavailable
- WordPress and other dependent applications unable to access database
- Required immediate intervention to restore service

---

## 3. Analysis

### Step 1: Check PVC Status - Bound and Healthy

```bash
[root@k8s-master1 ~]# kubectl get pvc -n database
NAME                     STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
mariadb-data-mariadb-0   Bound    pvc-ffbc1708-252f-48f8-bd87-70ee37726bc8   50Gi       RWO            nfs-retain     <unset>                 47h

[root@k8s-master1 ~]# kubectl describe pvc -n database
Name:          mariadb-data-mariadb-0
Namespace:     database
StorageClass:  nfs-retain
Status:        Bound
Volume:        pvc-ffbc1708-252f-48f8-bd87-70ee37726bc8
Labels:        app=mariadb
Capacity:      50Gi
Access Modes:  RWO
VolumeMode:    Filesystem
Used By:       mariadb-0
Events:        <none>
```

**Finding:** PVC is bound and healthy. Issue is not with PVC provisioning.

### Step 2: Check CSI NFS Pods - Recently Restarted

```bash
[root@k8s-master1 ~]# kubectl get pods -n kube-system | grep csi-nfs
csi-nfs-controller-7d8bbb9d89-4b7j5   5/5   Running   2 (4m29s ago)   8m22s
csi-nfs-controller-7d8bbb9d89-htrqk   5/5   Running   37 (49m ago)    4d8h
csi-nfs-node-52gb7                    3/3   Running   0               8m15s
csi-nfs-node-7c8ln                    3/3   Running   0               8m17s
csi-nfs-node-8d9bc                    3/3   Running   0               8m14s
csi-nfs-node-kx978                    3/3   Running   0               8m22s
csi-nfs-node-ppdqq                    3/3   Running   0               8m20s
csi-nfs-node-vxtxb                    3/3   Running   0               8m18s
```

**Finding:** All `csi-nfs-node` pods show age of ~8 minutes with 0 restarts = fresh pods from DaemonSet rollout. This is the root cause.

### Step 3: Check CSI Pods Location

```bash
[root@k8s-master1 ~]# kubectl get pods -n kube-system -o wide | grep csi-nfs
csi-nfs-controller-7d8bbb9d89-4b7j5   5/5   Running   2 (7m3s ago)   10m   10.0.54.10   k8s-worker1.lab.local   <none>   <none>
csi-nfs-node-vxtxb                    3/3   Running   0              10m   10.0.54.10   k8s-worker1.lab.local   <none>   <none>
```

### Step 4: Check MariaDB Pod Location

```bash
[root@k8s-master1 ~]# kubectl get pods -n database -o wide
NAME        READY   STATUS             RESTARTS       AGE     IP             NODE                    NOMINATED NODE   READINESS GATES
mariadb-0   1/2     CrashLoopBackOff   5 (104s ago)   4m44s   10.245.62.36   k8s-worker1.lab.local   <none>           <none>
```

**Finding:** MariaDB is on worker1. CSI node pod on worker1 (`csi-nfs-node-vxtxb`) was restarted ~10 minutes ago.

### Step 5: Get NFS Server Details from PV

```bash
[root@k8s-master1 ~]# kubectl get pv pvc-ffbc1708-252f-48f8-bd87-70ee37726bc8 -o yaml | grep -A5 nfs
    driver: nfs.csi.k8s.io
    volumeAttributes:
      server: 10.0.40.120
      subdir: pvc-ffbc1708-252f-48f8-bd87-70ee37726bc8
    volumeHandle: 10.0.40.120#volume1/k8s-prod#pvc-ffbc1708-252f-48f8-bd87-70ee37726bc8##
  mountOptions:
  - soft
  - timeo=30
  - retrans=3
```

**Finding:**
- NFS Server: 10.0.40.120
- Share: volume1/k8s-prod
- Subdir: pvc-ffbc1708-252f-48f8-bd87-70ee37726bc8
- Mount Options: `soft, timeo=30, retrans=3`

### Step 6: Check NFS Mount on Worker Node

```bash
[root@k8s-worker1 ~]# mount | grep mariadb
(no output)

[root@k8s-worker1 ~]# mount | grep nfs
(no output for the specific PVC mount)
```

**Finding:** Mount not visible or stale. CSI restart broke the mount handle.

### Step 7: Verify Data Exists on NFS Server

Accessed NFS server directly via web UI. Data files present and recently modified:
- `ibdata1` (12 MB) - InnoDB system tablespace
- `ib_logfile0` (96 MB) - InnoDB redo log - modified 04/06/2026 09:11
- `ibtmp1` (12 MB) - modified 04/06/2026 08:57
- `wordpress/` directory - WordPress database
- `mysql/`, `sys/`, `performance_schema/` directories

**Finding:** Data is intact on NFS server. Issue is mount connectivity, not data corruption.

### Failed Recovery Attempts

**Force Delete Pod - Still Fails on Same Node:**
```bash
[root@k8s-master1 ~]# kubectl delete pod mariadb-0 -n database --grace-period=0 --force
pod "mariadb-0" force deleted
# Pod recreated on same node with same stale mount. Still failing.
```

**Restart Kubelet on Worker1 - Still Fails:**
```bash
[root@k8s-worker1 ~]# systemctl restart kubelet
# Kubelet restart didn't clear CSI-managed NFS mount. Still failing.
```

**Why kubelet restart didn't work:** Kubelet does not manage CSI mounts directly. The CSI driver (csi-nfs-node DaemonSet pod) manages NFS mounts. Restarting kubelet alone does not restart or reset the CSI driver's mount state.

---

## 4. Root Cause

### Chain of Events

```
Flux applies CSI NFS driver changes (priorityClassName + replicas)
    ↓
Kubernetes rolls all csi-nfs-node DaemonSet pods
    ↓
csi-nfs-node on worker1 restarts
    ↓
Existing NFS mount for MariaDB PVC becomes stale
    ↓
MariaDB tries to access InnoDB files through stale mount
    ↓
NFS returns I/O errors (due to soft mount)
    ↓
InnoDB receives error 5 (EIO) and error 205 (NFS stale handle)
    ↓
InnoDB cannot continue, calls abort()
    ↓
MariaDB crashes, enters CrashLoopBackOff
```

### Why Only Worker1 Was Affected

| Node | Had MariaDB? | CSI Node Restarted? | Result |
|------|--------------|---------------------|--------|
| worker1 | YES (active mount) | YES | Stale mount → MariaDB crash |
| worker2 | NO | YES | No issue - no active mount to break |
| worker3 | NO | YES | No issue - no active mount to break |

The CSI restart affected all nodes equally, but only worker1 had an **active mount** for MariaDB at the time. Worker2 and worker3 had no mounts to break.

### Role of `soft` Mount Option

Current StorageClass mount options:
```yaml
mountOptions:
  - soft
  - timeo=30    # 3 second timeout
  - retrans=3   # 3 retries
```

With `soft` mount:
- After timeout (3 sec) × retries (3) = ~9 seconds
- NFS returns error to application instead of waiting
- MariaDB received I/O error and crashed

With `hard` mount (alternative):
- Would wait indefinitely for NFS to respond
- MariaDB would hang instead of crash
- When NFS recovers, would resume (data integrity preserved)

---

## 5. Solution

### Immediate Resolution: Cordon Worker1 and Move Pod to Worker2

```bash
# Step 1: Prevent new pods on worker1
[root@k8s-master1 ~]# kubectl cordon k8s-worker1.lab.local
node/k8s-worker1.lab.local cordoned

# Step 2: Force delete pod
[root@k8s-master1 ~]# kubectl delete pod mariadb-0 -n database --grace-period=0 --force
pod "mariadb-0" force deleted

# Step 3: Watch pod schedule to different node
[root@k8s-master1 ~]# kubectl get pods -n database -o wide -w
NAME        READY   STATUS        RESTARTS   AGE   IP       NODE                    NOMINATED NODE   READINESS GATES
mariadb-0   0/2     Init:0/1      0          0s    <none>   k8s-worker2.lab.local   <none>           <none>
mariadb-0   0/2     PodInitializing   0      3s    10.245.207.76   k8s-worker2.lab.local   <none>           <none>
```

**Result:** MariaDB running successfully on worker2 with fresh NFS mount!

### Reboot Worker1 to Clear Stale Handles

```bash
[root@k8s-worker1 ~]# reboot
```

**Note:** Full node reboot is thorough but slow (~2-3 minutes). See alternative below.

### Alternative: Restart CSI Node Pod (Faster - No Reboot Required)

Instead of rebooting the entire node, restarting only the CSI node pod on the affected worker clears stale mount handles:

```bash
# Step 1: Find the CSI node pod on the affected worker
[root@k8s-master1 ~]# kubectl get pods -n kube-system -o wide | grep csi-nfs-node | grep k8s-worker1
csi-nfs-node-vxtxb   3/3   Running   0   10m   10.0.54.10   k8s-worker1.lab.local   <none>   <none>

# Step 2: Delete the CSI node pod (DaemonSet will recreate it)
[root@k8s-master1 ~]# kubectl delete pod csi-nfs-node-vxtxb -n kube-system
pod "csi-nfs-node-vxtxb" deleted

# Step 3: Wait for new CSI pod to be ready (~10 seconds)
[root@k8s-master1 ~]# kubectl get pods -n kube-system | grep csi-nfs-node
csi-nfs-node-xxxxx   3/3   Running   0   15s   ...

# Step 4: Delete the application pod to get fresh mount
[root@k8s-master1 ~]# kubectl delete pod mariadb-0 -n database
```

**Why this works:** The CSI node pod manages all NFS mounts on that node. Deleting it forces the DaemonSet to create a fresh pod, which re-initializes mount handling.

**Comparison:**

| Method | Downtime | Speed | Scope |
|--------|----------|-------|-------|
| Node reboot | All pods on node | ~2-3 min | Everything reset |
| CSI pod restart | Only CSI-mounted pods | ~15 sec | Only NFS mounts |

### Permanent Solution: Created New StorageClass for Databases

Created `nfs-database` StorageClass with hard mount options:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-database
provisioner: nfs.csi.k8s.io
parameters:
  server: "10.0.40.120"
  share: "/volume1/k8s-dev"
reclaimPolicy: Retain
volumeBindingMode: Immediate
mountOptions:
  - hard
  - timeo=600    # 60 second timeout before retry
  - retrans=5    # 5 retries
  - intr         # Allows interrupt with SIGKILL if stuck
```

### Mount Options Trade-off Analysis

| Aspect | `soft` Mount | `hard` Mount | `hard` + `intr` |
|--------|--------------|--------------|-----------------|
| NFS brief hiccup | I/O error → crash | Waits → resumes | Waits → resumes |
| NFS prolonged outage | Repeated crashes | Hangs forever | Hangs (can force-kill) |
| Data integrity | Risk of corruption | Safe | Safe |
| Recovery | Restart pod | Wait or reboot | Wait or force-kill |
| Best for | Stateless apps | Databases | Databases |

### Recommended Mount Options by Workload

| Workload Type | Recommended Mount | Rationale |
|---------------|-------------------|-----------|
| Web apps (WordPress, Nginx) | `soft` | Crash & restart is better than hang |
| Monitoring (Prometheus, Grafana) | `soft` | Can rescrape data, shouldn't hang cluster |
| **Databases (MariaDB, PostgreSQL)** | `hard` + `intr` | Data integrity critical; hang is recoverable, corruption is not |

### Files Changed

| File | Change |
|------|--------|
| `kubernetes/dev/deployments/infrastructure/storage/storageclass.yaml` | Added `nfs-database` StorageClass |
| `kubernetes/prod/deployments/infrastructure/storage/storageclass.yaml` | Added `nfs-database` StorageClass |
| `kubernetes/dev/deployments/infrastructure/storage/nfs-csi-driver.yaml` | Added priorityClassName (triggered this issue) |
| `kubernetes/prod/deployments/infrastructure/storage/nfs-csi-driver.yaml` | Added priorityClassName |

### Prevention Measures

**Before CSI Driver Updates:**
1. Identify nodes with stateful workloads (databases)
2. Consider draining those nodes first
3. Or accept potential pod reschedule after update

---

## 6. Solution Risk

- **Risk Level:** Medium
- **Potential Impact:**
  - Moving pod to different node: Low risk - standard Kubernetes operation
  - Rebooting affected node: Medium risk - temporary loss of all workloads on that node (~2-3 min)
  - Restarting CSI node pod: Low risk - may briefly affect other CSI-mounted pods on that node
  - Changing StorageClass for new deployments: Low risk - does not affect existing PVCs
  - Patching existing PV mount options: Medium risk - requires pod restart, potential brief data access interruption

---

## 7. Impact After Fix

**Observed Results:**
- MariaDB running successfully on worker2 with fresh NFS mount immediately after cordon/move
- MariaDB running successfully on worker1 after node reboot
- No data loss - all InnoDB files intact on NFS server
- WordPress and dependent applications restored to normal operation
- New `nfs-database` StorageClass available for future database deployments

---

## 8. Notes

### Lessons Learned

1. **CSI DaemonSet restarts affect active mounts** - Rolling updates to CSI node pods can break existing mounts on that node.

2. **Soft mount fails fast, hard mount waits** - Neither is universally correct. Choose based on workload criticality.

3. **Databases need special consideration** - Unlike stateless apps, databases cannot simply crash and restart. I/O errors during write can corrupt tablespace.

4. **Kubelet restart does NOT fix CSI mount issues** - Kubelet doesn't manage CSI mounts. Restarting kubelet alone has no effect on stale NFS handles.

5. **Restarting CSI node pod clears stale mounts** - Deleting the `csi-nfs-node` pod on the affected worker forces the DaemonSet to create a fresh pod, clearing stale mount state. This is faster than a full node reboot.

6. **Node reboot is thorough but slow** - When CSI mount is broken, rebooting the node works but takes 2-3 minutes. Use CSI pod restart for faster recovery.

7. **Moving pod to different node is fastest recovery** - Cordon affected node, delete pod, let scheduler pick healthy node with fresh mount.

### Commands Reference

**Quick Reference - Recovery Speed:**

| Method | Speed | When to Use |
|--------|-------|-------------|
| Move to different node | ~30 sec | Immediate recovery needed |
| Restart CSI pod | ~15 sec | Want to fix the specific node |
| Node reboot | ~2-3 min | Multiple issues or thorough reset needed |

### Related Files

- `kubernetes/dev/deployments/infrastructure/storage/storageclass.yaml`
- `kubernetes/prod/deployments/infrastructure/storage/storageclass.yaml`
- `kubernetes/dev/deployments/infrastructure/storage/nfs-csi-driver.yaml`
- `kubernetes/prod/deployments/infrastructure/storage/nfs-csi-driver.yaml`

### References

- Case 3: NFS Hard Mount Causing Intermittent Pod Unresponsiveness
- Case 6: NFS Storage Complete Guide - Static to Dynamic
- [Linux NFS mount options](https://linux.die.net/man/5/nfs)
- [MariaDB InnoDB Error Codes](https://mariadb.com/kb/en/operating-system-error-codes/)
- [Kubernetes CSI NFS Driver](https://github.com/kubernetes-csi/csi-driver-nfs)

---

## 9. Workaround

**If MariaDB Enters CrashLoopBackOff with I/O Errors:**

**Option A: Move pod to different node (immediate recovery)**
1. Check if CSI pods recently restarted: `kubectl get pods -n kube-system | grep csi-nfs`
2. Cordon affected node: `kubectl cordon k8s-worker1.lab.local`
3. Delete pod to move to fresh node: `kubectl delete pod mariadb-0 -n database`
4. Uncordon after fixing the node

**Option B: Fix the affected node without reboot (faster)**
1. Restart CSI node pod on affected worker:
   ```bash
   kubectl delete pod <csi-nfs-node-xxx> -n kube-system
   ```
2. Wait ~10 seconds for new CSI pod to be ready
3. Delete application pod: `kubectl delete pod mariadb-0 -n database`

**Option C: Reboot affected node (thorough but slower)**
1. Cordon the node: `kubectl cordon k8s-worker1.lab.local`
2. Reboot: `ssh k8s-worker1 'reboot'`
3. Wait for node ready, then uncordon
