# Case 13: CSI NFS DaemonSet Restart Causes Stale Mount and MariaDB CrashLoopBackOff

## Status: RESOLVED
## Date: 2026-04-06
## Severity: High
## Environment: k8s-dev cluster (bare-metal kubeadm, 3 masters, 3 workers, Calico CNI, NFS CSI storage, Vault sidecar)
## Related: Case 5 (NFS Hard Mount Unresponsiveness), Case 6 (Complete NFS Storage Guide)

---

## 1. Issue Summary

MariaDB entered CrashLoopBackOff with InnoDB I/O errors after Flux reconciled CSI NFS driver configuration changes (priority classes + controller replicas). The CSI node DaemonSet restart caused existing NFS mounts to become stale on the node where MariaDB was running.

**Root Cause:** CSI NFS node pod restart invalidated existing NFS mount handles. MariaDB, using `soft` mount options, received I/O errors instead of blocking, causing InnoDB to crash.

**Resolution:** Moved MariaDB to a different worker node with fresh NFS mount. Rebooted affected node to clear stale handles.

---

## 2. Timeline of Events

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

---

## 3. Symptoms Observed

### 3.1 Pod Status - CrashLoopBackOff

```bash
[root@k8s-master1 ~]# kubectl get pods -n database
NAME        READY   STATUS             RESTARTS        AGE
mariadb-0   1/2     CrashLoopBackOff   5 (2m15s ago)   5m11s
```

### 3.2 MariaDB Container Logs - InnoDB I/O Errors

```bash
[root@k8s-master1 ~]# kubectl logs mariadb-0 -n database
Defaulted container "mariadb" out of: mariadb, vault-agent, vault-agent-init (init)
2026-04-06 19:40:14+00:00 [Note] [Entrypoint]: Entrypoint script for MariaDB Server 1:10.11.11+maria~ubu2204 started.
2026-04-06 19:40:15+00:00 [Warn] [Entrypoint]: /sys/fs/cgroup///memory.pressure not writable, functionality unavailable to MariaDB
2026-04-06 19:40:15+00:00 [Note] [Entrypoint]: Switching to dedicated user 'mysql'
2026-04-06 19:40:15+00:00 [Note] [Entrypoint]: Entrypoint script for MariaDB Server 1:10.11.11+maria~ubu2204 started.
2026-04-06 19:40:15+00:00 [Note] [Entrypoint]: MariaDB upgrade not required
2026-04-06 19:40:15 0 [Note] Starting MariaDB 10.11.11-MariaDB-ubu2204 source revision e69f8cae1a15e15b9e4f5e0f8497e1f17bdc81a4 server_uid vLxpHALrbQNZB2yqxQwOukyyUJ8= as process 1
2026-04-06 19:40:15 0 [Note] InnoDB: Compressed tables use zlib 1.2.11
2026-04-06 19:40:15 0 [Note] InnoDB: Number of transaction pools: 1
2026-04-06 19:40:15 0 [Note] InnoDB: Using crc32 + pclmulqdq instructions
2026-04-06 19:40:15 0 [Warning] mysqld: io_uring_queue_init() failed with errno 1
2026-04-06 19:40:15 0 [Warning] InnoDB: liburing disabled: falling back to innodb_use_native_aio=OFF
2026-04-06 19:40:15 0 [Note] InnoDB: Initializing buffer pool, total size = 128.000MiB, chunk size = 2.000MiB
2026-04-06 19:40:15 0 [Note] InnoDB: Completed initialization of buffer pool
2026-04-06 19:40:15 0 [Note] InnoDB: Buffered log writes (block size=512 bytes)
2026-04-06 19:40:15 0 [ERROR] InnoDB: Operating system error number 5 in a file operation.
2026-04-06 19:40:15 0 [ERROR] InnoDB: Error number 5 means 'Input/output error'
2026-04-06 19:40:15 0 [Note] InnoDB: Some operating system error numbers are described at https://mariadb.com/kb/en/library/operating-system-error-codes/
2026-04-06 19:40:15 0 [ERROR] InnoDB: File (unknown): 'close' returned OS error 205. Cannot continue operation
260406 19:40:15 [ERROR] mysqld got signal 6 ;
```

**Key Error Lines:**
- `InnoDB: Operating system error number 5` - Input/output error (EIO)
- `InnoDB: Error number 5 means 'Input/output error'`
- `InnoDB: File (unknown): 'close' returned OS error 205` - NFS-specific stale handle error

### 3.3 Pod Events - Container Restart Loop

```bash
[root@k8s-master1 ~]# kubectl describe pod mariadb-0 -n database
...
Events:
  Type     Reason     Age               From               Message
  ----     ------     ----              ----               -------
  Normal   Scheduled  46s               default-scheduler  Successfully assigned database/mariadb-0 to k8s-worker1.lab.local
  Normal   Pulled     45s               kubelet            Container image "hashicorp/vault:1.21.2" already present on machine
  Normal   Created    45s               kubelet            Created container vault-agent-init
  Normal   Started    45s               kubelet            Started container vault-agent-init
  Normal   Pulled     44s               kubelet            Container image "hashicorp/vault:1.21.2" already present on machine
  Normal   Created    44s               kubelet            Created container vault-agent
  Normal   Started    44s               kubelet            Started container vault-agent
  Normal   Pulled     7s (x4 over 44s)  kubelet            Container image "mariadb:10.11.11" already present on machine
  Normal   Created    7s (x4 over 44s)  kubelet            Created container mariadb
  Normal   Started    7s (x4 over 44s)  kubelet            Started container mariadb
  Warning  BackOff    3s (x9 over 40s)  kubelet            Back-off restarting failed container mariadb
```

---

## 4. Investigation Steps

### 4.1 Check PVC Status - Bound and Healthy

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
Annotations:   pv.kubernetes.io/bind-completed: yes
               pv.kubernetes.io/bound-by-controller: yes
               volume.beta.kubernetes.io/storage-provisioner: nfs.csi.k8s.io
               volume.kubernetes.io/storage-provisioner: nfs.csi.k8s.io
Finalizers:    [kubernetes.io/pvc-protection]
Capacity:      50Gi
Access Modes:  RWO
VolumeMode:    Filesystem
Used By:       mariadb-0
Events:        <none>
```

**Finding:** PVC is bound and healthy. Issue is not with PVC provisioning.

### 4.2 Check CSI NFS Pods - Recently Restarted

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

### 4.3 Check CSI Pods Location

```bash
[root@k8s-master1 ~]# kubectl get pods -n kube-system -o wide | grep csi-nfs
csi-nfs-controller-7d8bbb9d89-4b7j5   5/5   Running   2 (7m3s ago)   10m   10.0.54.10   k8s-worker1.lab.local   <none>   <none>
csi-nfs-controller-7d8bbb9d89-htrqk   5/5   Running   37 (52m ago)   4d8h  10.0.54.12   k8s-worker3.lab.local   <none>   <none>
csi-nfs-node-52gb7                    3/3   Running   0              10m   10.0.51.12   k8s-master3.lab.local   <none>   <none>
csi-nfs-node-7c8ln                    3/3   Running   0              10m   10.0.51.10   k8s-master1.lab.local   <none>   <none>
csi-nfs-node-8d9bc                    3/3   Running   0              10m   10.0.54.11   k8s-worker2.lab.local   <none>   <none>
csi-nfs-node-kx978                    3/3   Running   0              10m   10.0.51.11   k8s-master2.lab.local   <none>   <none>
csi-nfs-node-ppdqq                    3/3   Running   0              10m   10.0.54.12   k8s-worker3.lab.local   <none>   <none>
csi-nfs-node-vxtxb                    3/3   Running   0              10m   10.0.54.10   k8s-worker1.lab.local   <none>   <none>
```

### 4.4 Check MariaDB Pod Location

```bash
[root@k8s-master1 ~]# kubectl get pods -n database -o wide
NAME        READY   STATUS             RESTARTS       AGE     IP             NODE                    NOMINATED NODE   READINESS GATES
mariadb-0   1/2     CrashLoopBackOff   5 (104s ago)   4m44s   10.245.62.36   k8s-worker1.lab.local   <none>           <none>
```

**Finding:** MariaDB is on worker1. CSI node pod on worker1 (`csi-nfs-node-vxtxb`) was restarted ~10 minutes ago.

### 4.5 Get NFS Server Details from PV

```bash
[root@k8s-master1 ~]# kubectl get pv pvc-ffbc1708-252f-48f8-bd87-70ee37726bc8 -o yaml | grep -A5 nfs
    pv.kubernetes.io/provisioned-by: nfs.csi.k8s.io
    volume.kubernetes.io/provisioner-deletion-secret-name: ""
    volume.kubernetes.io/provisioner-deletion-secret-namespace: ""
  creationTimestamp: "2026-04-04T19:52:38Z"
  finalizers:
  - kubernetes.io/pv-protection
--
    driver: nfs.csi.k8s.io
    volumeAttributes:
      csi.storage.k8s.io/pv/name: pvc-ffbc1708-252f-48f8-bd87-70ee37726bc8
      csi.storage.k8s.io/pvc/name: mariadb-data-mariadb-0
      csi.storage.k8s.io/pvc/namespace: database
      server: 10.0.40.120
--
      storage.kubernetes.io/csiProvisionerIdentity: 1775285926223-3529-nfs.csi.k8s.io
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

### 4.6 Check NFS Mount on Worker Node

```bash
[root@k8s-worker1 ~]# mount | grep mariadb
(no output)

[root@k8s-worker1 ~]# mount | grep nfs
(no output for the specific PVC mount)
```

**Finding:** Mount not visible or stale. CSI restart broke the mount handle.

### 4.7 Verify Data Exists on NFS Server

Accessed NFS server directly via web UI. Data files present and recently modified:
- `ibdata1` (12 MB) - InnoDB system tablespace
- `ib_logfile0` (96 MB) - InnoDB redo log - modified 04/06/2026 09:11
- `ibtmp1` (12 MB) - modified 04/06/2026 08:57
- `wordpress/` directory - WordPress database
- `mysql/`, `sys/`, `performance_schema/` directories

**Finding:** Data is intact on NFS server. Issue is mount connectivity, not data corruption.

---

## 5. Failed Recovery Attempts

### 5.1 Force Delete Pod - Still Fails on Same Node

```bash
[root@k8s-master1 ~]# kubectl delete pod mariadb-0 -n database --grace-period=0 --force
Warning: Immediate deletion does not wait for confirmation that the running resource has been terminated.
pod "mariadb-0" force deleted

[root@k8s-master1 ~]# kubectl get pods -n database -o wide
NAME        READY   STATUS             RESTARTS     AGE   IP             NODE                    NOMINATED NODE   READINESS GATES
mariadb-0   1/2     CrashLoopBackOff   1 (4s ago)   9s    10.245.62.35   k8s-worker1.lab.local   <none>           <none>
```

**Result:** Pod recreated on same node with same stale mount. Still failing.

### 5.2 Restart Kubelet on Worker1 - Still Fails

```bash
[root@k8s-worker1 ~]# systemctl restart kubelet
```

```bash
[root@k8s-master1 ~]# kubectl get pods -n database -o wide
NAME        READY   STATUS             RESTARTS      AGE     IP             NODE                    NOMINATED NODE   READINESS GATES
mariadb-0   1/2     CrashLoopBackOff   6 (10s ago)   5m12s   10.245.62.36   k8s-worker1.lab.local   <none>           <none>
```

**Result:** Kubelet restart didn't clear CSI-managed NFS mount. Still failing.

**Why kubelet restart didn't work:** Kubelet does not manage CSI mounts directly. The CSI driver (csi-nfs-node DaemonSet pod) manages NFS mounts. Restarting kubelet alone does not restart or reset the CSI driver's mount state.

---

## 6. Successful Resolution

### 6.1 Cordon Worker1 and Move Pod to Worker2

```bash
# Step 1: Prevent new pods on worker1
[root@k8s-master1 ~]# kubectl cordon k8s-worker1.lab.local
node/k8s-worker1.lab.local cordoned

# Step 2: Force delete pod
[root@k8s-master1 ~]# kubectl delete pod mariadb-0 -n database --grace-period=0 --force
Warning: Immediate deletion does not wait for confirmation that the running resource has been terminated.
pod "mariadb-0" force deleted

# Step 3: Watch pod schedule to different node
[root@k8s-master1 ~]# kubectl get pods -n database -o wide -w
NAME        READY   STATUS        RESTARTS   AGE   IP       NODE                    NOMINATED NODE   READINESS GATES
mariadb-0   0/2     Init:0/1      0          0s    <none>   k8s-worker2.lab.local   <none>           <none>
mariadb-0   0/2     Init:0/1      0          2s    <none>   k8s-worker2.lab.local   <none>           <none>
mariadb-0   0/2     PodInitializing   0      3s    10.245.207.76   k8s-worker2.lab.local   <none>           <none>
```

### 6.2 Verify Pod Running on Worker2

```bash
[root@k8s-master1 ~]# kubectl get pods -n database -o wide
NAME        READY   STATUS    RESTARTS   AGE   IP              NODE                    NOMINATED NODE   READINESS GATES
mariadb-0   2/2     Running   0          49s   10.245.207.76   k8s-worker2.lab.local   <none>           <none>
```

**Result:** MariaDB running successfully on worker2 with fresh NFS mount!

### 6.3 Reboot Worker1 to Clear Stale Handles (What We Did)

```bash
[root@k8s-worker1 ~]# reboot
```

**Note:** Full node reboot is thorough but slow (~2-3 minutes). See section 6.3.1 for faster alternative.

### 6.3.1 Alternative: Restart CSI Node Pod (Faster - No Reboot Required)

Instead of rebooting the entire node, restarting only the CSI node pod on the affected worker would have cleared the stale mount handles:

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

**Why this works:** The CSI node pod manages all NFS mounts on that node. Deleting it forces the DaemonSet to create a fresh pod, which re-initializes mount handling. The application pod then gets a fresh mount when recreated.

**Comparison:**

| Method | Downtime | Speed | Scope |
|--------|----------|-------|-------|
| Node reboot | All pods on node | ~2-3 min | Everything reset |
| CSI pod restart | Only CSI-mounted pods | ~15 sec | Only NFS mounts |

### 6.4 Move MariaDB Back to Worker1

```bash
# Uncordon worker1 after reboot
[root@k8s-master1 ~]# kubectl uncordon k8s-worker1.lab.local
node/k8s-worker1.lab.local uncordoned

# Cordon worker2 to force move
[root@k8s-master1 ~]# kubectl cordon k8s-worker2.lab.local
node/k8s-worker2.lab.local cordoned

# Delete pod
[root@k8s-master1 ~]# kubectl delete pod mariadb-0 -n database

# Verify running on worker1
[root@k8s-master1 ~]# kubectl get pods -n database -o wide
NAME        READY   STATUS    RESTARTS   AGE   IP              NODE                    NOMINATED NODE   READINESS GATES
mariadb-0   2/2     Running   0          30s   10.245.62.XX    k8s-worker1.lab.local   <none>           <none>

# Uncordon worker2
[root@k8s-master1 ~]# kubectl uncordon k8s-worker2.lab.local
node/k8s-worker2.lab.local uncordoned
```

**Result:** MariaDB running on worker1 after reboot cleared stale NFS handles.

---

## 7. Root Cause Analysis

### 7.1 Chain of Events

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

### 7.2 Why Only Worker1 Was Affected

| Node | Had MariaDB? | CSI Node Restarted? | Result |
|------|--------------|---------------------|--------|
| worker1 | YES (active mount) | YES | Stale mount → MariaDB crash |
| worker2 | NO | YES | No issue - no active mount to break |
| worker3 | NO | YES | No issue - no active mount to break |

The CSI restart affected all nodes equally, but only worker1 had an **active mount** for MariaDB at the time. Worker2 and worker3 had no mounts to break.

### 7.3 Role of `soft` Mount Option

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

## 8. Mount Options Trade-off Analysis

### 8.1 Previous Issue - Case 5 (Hard Mount)

In Case 5, `hard` mount caused pods to hang indefinitely when NFS had transient issues:
- Nginx pods hung forever
- Could not serve HTTP traffic
- Required node reboot to recover
- Led to decision to switch to `soft` mount

### 8.2 Current Issue (Soft Mount)

With `soft` mount during CSI restart:
- MariaDB received I/O errors
- InnoDB crashed immediately
- Potential risk of data corruption
- Required moving to different node

### 8.3 Comparison Matrix

| Aspect | `soft` Mount | `hard` Mount | `hard` + `intr` |
|--------|--------------|--------------|-----------------|
| NFS brief hiccup | I/O error → crash | Waits → resumes | Waits → resumes |
| NFS prolonged outage | Repeated crashes | Hangs forever | Hangs (can force-kill) |
| Data integrity | Risk of corruption | Safe | Safe |
| Recovery | Restart pod | Wait or reboot | Wait or force-kill |
| Best for | Stateless apps | Databases | Databases |

### 8.4 Recommended Mount Options by Workload

| Workload Type | Recommended Mount | Rationale |
|---------------|-------------------|-----------|
| Web apps (WordPress, Nginx) | `soft` | Crash & restart is better than hang |
| Monitoring (Prometheus, Grafana) | `soft` | Can rescrape data, shouldn't hang cluster |
| **Databases (MariaDB, PostgreSQL)** | `hard` + `intr` | Data integrity critical; hang is recoverable, corruption is not |

---

## 9. Permanent Solution Plan

### 9.1 Created New StorageClass for Databases

Created `nfs-database` StorageClass with hard mount options:

```yaml
# kubernetes/dev/deployments/infrastructure/storage/storageclass.yaml
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

### 9.2 Existing StorageClasses Unchanged

| StorageClass | Mount Type | Used By | Change |
|--------------|------------|---------|--------|
| `nfs-retain` | soft | WordPress, Prometheus, Grafana | No change |
| `nfs-delete` | soft | Temporary workloads | No change |
| `nfs-database` | hard + intr | Future database deployments | **NEW** |

### 9.3 Why Not Migrate Existing MariaDB

Migrating existing MariaDB PVC to new StorageClass would require:
1. Backup all data
2. Delete StatefulSet and PVC
3. Recreate StatefulSet with new StorageClass
4. Restore data

This is risky and unnecessary. Alternative approach:

### 9.4 Alternative: Patch Existing PV (If Desired)

Can change mount options on existing PV without migration:

```bash
kubectl patch pv pvc-ffbc1708-252f-48f8-bd87-70ee37726bc8 --type='json' -p='[
  {"op": "replace", "path": "/spec/mountOptions", "value": ["hard", "timeo=600", "retrans=5", "intr"]}
]'
kubectl delete pod mariadb-0 -n database
```

---

## 10. Final Decision

### 10.1 Current State (Keeping)

- MariaDB remains on `nfs-retain` StorageClass with `soft` mount
- This matches existing behavior and Case 5 resolution
- NFS server (Synology) is stable; CSI restart was unusual one-time event

### 10.2 Future Protection

- `nfs-database` StorageClass available for new database deployments
- Can patch existing PV to `hard` + `intr` if needed
- Document CSI restart impact for future maintenance

### 10.3 Operational Procedures

**Before CSI Driver Updates:**
1. Identify nodes with stateful workloads (databases)
2. Consider draining those nodes first
3. Or accept potential pod reschedule after update

**If MariaDB Enters CrashLoopBackOff with I/O Errors:**

*Option A: Move pod to different node (immediate recovery)*
1. Check if CSI pods recently restarted: `kubectl get pods -n kube-system | grep csi-nfs`
2. Cordon affected node: `kubectl cordon k8s-worker1.lab.local`
3. Delete pod to move to fresh node: `kubectl delete pod mariadb-0 -n database`
4. Uncordon after fixing the node

*Option B: Fix the affected node without reboot (faster)*
1. Restart CSI node pod on affected worker:
   ```bash
   kubectl delete pod <csi-nfs-node-xxx> -n kube-system
   ```
2. Wait ~10 seconds for new CSI pod to be ready
3. Delete application pod: `kubectl delete pod mariadb-0 -n database`

*Option C: Reboot affected node (thorough but slower)*
1. Cordon the node: `kubectl cordon k8s-worker1.lab.local`
2. Reboot: `ssh k8s-worker1 'reboot'`
3. Wait for node ready, then uncordon

**Quick Reference - Recovery Speed:**

| Method | Speed | When to Use |
|--------|-------|-------------|
| Move to different node | ~30 sec | Immediate recovery needed |
| Restart CSI pod | ~15 sec | Want to fix the specific node |
| Node reboot | ~2-3 min | Multiple issues or thorough reset needed |

---

## 11. Lessons Learned

1. **CSI DaemonSet restarts affect active mounts** - Rolling updates to CSI node pods can break existing mounts on that node.

2. **Soft mount fails fast, hard mount waits** - Neither is universally correct. Choose based on workload criticality.

3. **Databases need special consideration** - Unlike stateless apps, databases cannot simply crash and restart. I/O errors during write can corrupt tablespace.

4. **Kubelet restart does NOT fix CSI mount issues** - Kubelet doesn't manage CSI mounts. Restarting kubelet alone has no effect on stale NFS handles.

5. **Restarting CSI node pod clears stale mounts** - Deleting the `csi-nfs-node` pod on the affected worker forces the DaemonSet to create a fresh pod, clearing stale mount state. This is faster than a full node reboot.

6. **Node reboot is thorough but slow** - When CSI mount is broken, rebooting the node works but takes 2-3 minutes. Use CSI pod restart for faster recovery.

7. **Moving pod to different node is fastest recovery** - Cordon affected node, delete pod, let scheduler pick healthy node with fresh mount.

---

## 12. References

- Case 5: NFS Hard Mount Causing Intermittent Pod Unresponsiveness
- Case 6: NFS Storage Complete Guide - Static to Dynamic
- [Linux NFS mount options](https://linux.die.net/man/5/nfs)
- [MariaDB InnoDB Error Codes](https://mariadb.com/kb/en/operating-system-error-codes/)
- [Kubernetes CSI NFS Driver](https://github.com/kubernetes-csi/csi-driver-nfs)

---

## 13. Files Changed

| File | Change |
|------|--------|
| `kubernetes/dev/deployments/infrastructure/storage/storageclass.yaml` | Added `nfs-database` StorageClass |
| `kubernetes/prod/deployments/infrastructure/storage/storageclass.yaml` | Added `nfs-database` StorageClass |
| `kubernetes/dev/deployments/infrastructure/storage/nfs-csi-driver.yaml` | Added priorityClassName (triggered this issue) |
| `kubernetes/prod/deployments/infrastructure/storage/nfs-csi-driver.yaml` | Added priorityClassName |
