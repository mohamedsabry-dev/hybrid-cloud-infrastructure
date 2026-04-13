# TS-K8S-015 | 2026-04-06 | RESOLVED

## 1. Context

- **System:** CSI NFS Driver, MariaDB StatefulSet
- **Environment:** k8s-dev cluster (bare-metal kubeadm, 3 masters, 3 workers, Calico CNI, NFS CSI storage, Vault sidecar)
- **Related Components:** NFS storage (Synology 10.0.40.120), Flux GitOps, InnoDB
- **Discovered During:** Flux reconciliation of CSI NFS driver configuration changes (priority classes + controller replicas)
- **Related Cases:**
  - TS-K8S-003 — NFS hard mount pod hangs (introduced soft mount that caused this crash)
  - TS-K8S-006 — Complete NFS storage guide
  - TS-K8S-007 — InnoDB O_DIRECT NFS incompatibility (same database + NFS fragility)
  - TS-K8S-018 — CSI controller network placement (companion case — CSI deployment decisions causing storage failures)
  - TS-K8S-026 — Released PV cleanup (cordon/move in this case created Released PVs that were cleaned in TS-K8S-026)

---

## 2. Issue

**Symptom:** MariaDB entered CrashLoopBackOff with InnoDB I/O errors after Flux reconciled CSI NFS driver configuration changes.

**Error Messages:**
- `InnoDB: Operating system error number 5` — Input/output error (EIO)
- `InnoDB: File (unknown): 'close' returned OS error 205` — NFS stale handle error

**Timeline:**

| Time | Event |
|------|-------|
| ~19:30 | Flux applied CSI NFS driver changes (priorityClassName + replicas=2) |
| ~19:30 | All csi-nfs-node DaemonSet pods restarted on all nodes |
| ~19:35 | MariaDB on worker1 started failing with I/O errors |
| ~19:40 | MariaDB entered CrashLoopBackOff |
| ~19:50 | Diagnosed as stale NFS mount |
| ~19:55 | Cordoned worker1, moved MariaDB to worker2 — WORKING |
| ~20:05 | Rebooted worker1 to clear stale handles |
| ~20:10 | Moved MariaDB back to worker1 — WORKING |

**MariaDB Container Logs:**
```
2026-04-06 19:40:15 0 [ERROR] InnoDB: Operating system error number 5 in a file operation.
2026-04-06 19:40:15 0 [ERROR] InnoDB: Error number 5 means 'Input/output error'
2026-04-06 19:40:15 0 [ERROR] InnoDB: File (unknown): 'close' returned OS error 205. Cannot continue operation
260406 19:40:15 [ERROR] mysqld got signal 6 ;
```

---

## 3. Analysis

### Step 1: Check PVC Status

```bash
kubectl get pvc -n database
# mariadb-data-mariadb-0   Bound   pvc-ffbc1708-...   50Gi   RWO   nfs-retain
```

Finding: PVC is bound and healthy. Issue is not with PVC provisioning.

### Step 2: Check CSI NFS Pods — Recently Restarted

```bash
kubectl get pods -n kube-system | grep csi-nfs
# csi-nfs-node-52gb7   3/3   Running   0   8m15s
# csi-nfs-node-7c8ln   3/3   Running   0   8m17s
# (all nodes show ~8 minutes age, 0 restarts = fresh from DaemonSet rollout)
```

Finding: All csi-nfs-node pods freshly rolled out by the Flux change — this broke existing mounts.

### Step 3: Check MariaDB Pod Location

```bash
kubectl get pods -n database -o wide
# mariadb-0   CrashLoopBackOff   k8s-worker1.lab.local
```

Finding: MariaDB on worker1. csi-nfs-node on worker1 restarted ~10 minutes ago.

### Step 4: Verify Data Intact on NAS

Data confirmed present on NAS:
- `ibdata1`, `ib_logfile0`, `ibtmp1` all present and recently modified
- `wordpress/` directory present

Finding: Data is intact. Issue is mount connectivity, not data corruption.

### Step 5: Why kubelet Restart Didn't Work

```bash
systemctl restart kubelet
# Still failing
```

Kubelet does not manage CSI mounts directly. The CSI driver (csi-nfs-node DaemonSet pod) manages NFS mounts. Restarting kubelet has no effect on stale CSI mount state.

---

## 4. Root Cause

### Chain of Events

```
Flux applies CSI NFS driver changes (priorityClassName + replicas)
    ↓
Kubernetes rolls all csi-nfs-node DaemonSet pods on all nodes
    ↓
csi-nfs-node on worker1 restarts — existing NFS mount for MariaDB PVC becomes stale
    ↓
MariaDB tries to access InnoDB files through stale mount
    ↓
soft mount (from TS-K8S-003 fix) returns I/O error after timeout instead of waiting
    ↓
InnoDB receives error 5 (EIO) and error 205 (NFS stale handle)
    ↓
InnoDB cannot continue → calls abort() → MariaDB crashes → CrashLoopBackOff
```

### The Soft Mount Contribution

The `soft` mount option introduced in TS-K8S-003 was correct for nginx (stateless, replicated). For MariaDB it is wrong:

| Mount | Behavior on stale NFS | Result for MariaDB |
|---|---|---|
| `soft` | Returns I/O error after timeout | InnoDB crash → CrashLoopBackOff |
| `hard` | Waits indefinitely for NFS | MariaDB hangs but resumes when NFS recovers |
| `hard` + `intr` | Waits but can be interrupted with SIGKILL | Hang + manual recovery possible |

The same mount option that saved nginx (soft) was what crashed MariaDB.

**Rule:** soft mount = correct for stateless apps. hard mount = correct for databases.

### Why Only Worker1 Was Affected

| Node | Had MariaDB? | CSI Node Restarted? | Result |
|------|--------------|---------------------|--------|
| worker1 | YES (active mount) | YES | Stale mount → crash |
| worker2 | NO | YES | No active mount → no issue |
| worker3 | NO | YES | No active mount → no issue |

---

## 5. Solution

### Immediate: Cordon Worker1, Move Pod to Worker2

```bash
# Prevent new pods on worker1
kubectl cordon k8s-worker1.lab.local

# Force delete pod (StatefulSet recreates it on another node)
kubectl delete pod mariadb-0 -n database --grace-period=0 --force

# Watch pod schedule to worker2 with fresh mount
kubectl get pods -n database -o wide -w
# mariadb-0   PodInitializing   k8s-worker2.lab.local
# mariadb-0   Running 2/2       k8s-worker2.lab.local ✓
```

### Fix the Affected Node

**Option A — Restart CSI node pod (faster, ~15 seconds):**
```bash
# Find CSI node pod on the affected worker
kubectl get pods -n kube-system -o wide | grep csi-nfs-node | grep k8s-worker1

# Delete it — DaemonSet recreates it immediately
kubectl delete pod <csi-nfs-node-pod> -n kube-system

# Wait ~10 seconds, then delete app pod to get fresh mount
kubectl delete pod mariadb-0 -n database
```

**Option B — Reboot node (thorough, ~2-3 minutes):**
```bash
ssh k8s-worker1 'reboot'
# Wait for node Ready
kubectl uncordon k8s-worker1.lab.local
```

### Recovery Method Comparison

| Method | Downtime | Speed | When to use |
|--------|----------|-------|-------------|
| Move pod to different node | ~30s | Fast | Immediate recovery needed |
| Restart CSI node pod | ~15s | Fastest | Fix specific node, minimal impact |
| Node reboot | ~2-3min | Slow | Multiple issues or thorough reset |

### Permanent Fix: nfs-database StorageClass

Created `nfs-database` StorageClass with hard mount for all database workloads:

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
  - nfsvers=3
  - nolock
  - hard
  - timeo=600    # 60s timeout per retry
  - retrans=5    # 5 retries before giving up
  - intr         # allows SIGKILL interrupt if stuck
```

With hard + intr:
- Brief NFS disruption → MariaDB waits → resumes when NFS recovers
- Prolonged NFS outage → MariaDB hangs → can be force-killed if needed
- No I/O errors → no InnoDB crash → no data corruption risk

### ⚠️ Pending Action: Migrate MariaDB PVC to nfs-database

Current MariaDB PVC still uses `nfs-retain` (soft mount). To fully prevent recurrence, MariaDB should be migrated to `nfs-database` StorageClass. This requires:

```bash
# 1. Backup MariaDB data first
# 2. Delete MariaDB StatefulSet and PVC
# 3. Update StatefulSet volumeClaimTemplate to storageClassName: nfs-database
# 4. Redeploy — CSI creates new PVC with hard mount
# 5. Restore data
```

Until this migration is done, the same crash can occur if csi-nfs-node restarts again.

### Before CSI Driver Updates — Prevention

Before any CSI NFS driver update that rolls DaemonSet pods:

1. Identify nodes with stateful database workloads
2. Either drain those nodes first or accept potential pod reschedule
3. Test recovery procedure is documented and practiced

---

## 6. Solution Risk

- **Risk Level:** Medium
- Moving pod to different node: Low risk — standard K8s operation
- Rebooting node: Medium risk — temporary loss of all workloads on that node
- Restarting CSI pod: Low risk — may briefly affect other CSI-mounted pods on same node
- New StorageClass for future deployments: Low risk — does not affect existing PVCs

---

## 7. Impact After Fix

- MariaDB running successfully on worker2 immediately after cordon/move
- MariaDB running on worker1 after reboot
- No data loss — all InnoDB files intact on NAS
- WordPress and dependent applications restored
- `nfs-database` StorageClass available for future database deployments

---

## 8. Notes

### Key Lessons

1. **CSI DaemonSet restarts break active mounts** — Any update to CSI node pods can affect pods with active NFS mounts on that node
2. **Soft mount crashes databases** — TS-K8S-003 fix was correct for nginx, wrong for MariaDB
3. **Kubelet restart does NOT fix CSI mount issues** — CSI driver manages mounts, not kubelet
4. **Restarting CSI node pod clears stale mounts** — faster than full node reboot
5. **Moving pod to different node is fastest recovery** — works immediately with no node-level fix needed
6. **`Running` status doesn't mean healthy** — pod accepts connections but I/O can be stuck

### Mount Options by Workload — Final Decision

| Workload | StorageClass | Mount Type | Rationale |
|---|---|---|---|
| Nginx, WordPress, static | nfs-retain | soft | Crash + restart > hang |
| Prometheus, Grafana, Loki | nfs-retain | soft | Can rescrape, should not hang |
| **MariaDB, PostgreSQL** | **nfs-database** | **hard + intr** | **Data integrity > availability** |

### Commands Reference

```bash
# Check CSI controller/node pod locations
kubectl get pods -n kube-system -o wide | grep csi-nfs

# Cordon a node
kubectl cordon <node-name>
kubectl uncordon <node-name>

# Force delete StatefulSet pod
kubectl delete pod <pod-name> -n <namespace> --grace-period=0 --force

# Restart CSI node pod on specific worker
kubectl get pods -n kube-system -o wide | grep csi-nfs-node | grep <worker-name>
kubectl delete pod <csi-nfs-node-pod> -n kube-system

# Check NFS mount options on a node
ssh <worker-node> 'mount | grep nfs'
```

---

## 9. Workaround

**Immediate recovery if MariaDB enters CrashLoopBackOff with I/O errors:**

```bash
# Option A: Move to different node
kubectl cordon <affected-worker>
kubectl delete pod mariadb-0 -n database --grace-period=0 --force
kubectl uncordon <affected-worker>   # after fixing it

# Option B: Fix the node without reboot
kubectl delete pod <csi-nfs-node-on-affected-worker> -n kube-system
# Wait ~10s
kubectl delete pod mariadb-0 -n database
```