# TS-K8S-003 | 2026-03-31 | RESOLVED

## 1. Context

- **System:** NFS Storage / Kubernetes Pods / NGINX Deployment
- **Environment:** k8s-dev cluster (bare-metal kubeadm, 3 workers, Calico CNI, NFS storage, Vault sidecar)
- **Related Components:** NFS server (10.0.40.120), PersistentVolume, StorageClass, nginx deployment
- **Discovered During:** External NGINX reverse proxy load-balancing test across three K8s workers
- **Related Cases:**
  - TS-K8S-006 — Complete NFS storage guide (architecture update from this case)
  - TS-K8S-007 — InnoDB O_DIRECT NFS incompatibility (soft mount caused MariaDB crash — opposite tradeoff)
  - TS-K8S-015 — Stale NFS mount on CSI restart (soft mount caused MariaDB CrashLoopBackOff)

---

## 2. Issue

**Symptom:** Pods with NFS-backed volumes intermittently hung and stopped serving traffic. Nginx accepted TCP connections but never responded with HTTP.

**Test Configuration:**
External NGINX reverse proxy (LXC container) load-balancing across three K8s workers on NodePort 30080. Backend: nginx deployment with 3 replicas serving static file from NFS PersistentVolume.

```nginx
upstream k8s_workers {
    least_conn;
    server 10.0.64.10:30080;
    server 10.0.64.11:30080;
    server 10.0.64.12:30080;
}
```

**NGINX upstream log showed retries across workers:**
```
192.168.100.223 - [31/Mar/2026:20:14:26] "GET / HTTP/1.1" 200 upstream: 10.0.64.10:30080, 10.0.64.11:30080
```
Two workers in one line = retry happened.

**All three workers tried, client gave up (499):**
```
192.168.100.223 - [31/Mar/2026:20:17:45] "GET / HTTP/1.1" 499 upstream: 10.0.64.12:30080, 10.0.64.11:30080, 10.0.64.10:30080
```

Browser masked the issue (auto-retry). `curl` exposed the hang clearly.

**Impact:** Application unresponsive, load balancer retrying across all workers, eventual client timeout.

---

## 3. Analysis

### Step 1: Network Connectivity (Ruled Out)

```bash
ping 10.0.64.10  # 0% packet loss, ~2.9ms
ping 10.0.64.11  # 0% packet loss, ~3.0ms
ping 10.0.64.12  # 0% packet loss, ~3.0ms
```

### Step 2: NodePort Test (TCP connects, HTTP hangs)

```bash
curl http://10.0.64.10:30080  # hangs
curl http://10.0.64.11:30080  # hangs intermittently
curl http://10.0.64.12:30080  # hangs intermittently
```

TCP connected but no HTTP response. Problem above TCP layer.

### Step 3: Calico BGP (Ruled Out)

```bash
calicoctl node status
# All peers: up | Established
```

### Step 4: ClusterIP Test (Critical Finding)

```bash
curl http://10.96.229.52:8080  # Hello from NFS! (first)
curl http://10.96.229.52:8080  # hangs (second)
curl http://10.96.229.52:8080  # hangs (third)
```

ClusterIP itself hung intermittently. Problem at Pod level, not NGINX/NodePort/Calico.

### Step 5: Pod IP Direct Test (Isolation)

```bash
kubectl get pods -n testing -o wide
# nginx-test-858cd7c5cb-52q7x  2/2  Running  k8s-worker3  10.244.29.154
# nginx-test-858cd7c5cb-7vmzj  2/2  Running  k8s-worker2  10.244.207.88
# nginx-test-858cd7c5cb-d2t65  2/2  Running  k8s-worker1  10.244.62.54

curl http://10.244.62.54:80   # Hello from NFS! (worker1 - healthy)
curl http://10.244.207.88:80  # hangs (worker2 - stuck)
curl http://10.244.29.154:80  # hangs (worker3 - stuck)
```

**Definitive isolation:** Problem at Pod IP level.

### Step 6: Container Logs (Clean)

```bash
kubectl logs nginx-test-858cd7c5cb-52q7x -n testing -c nginx
kubectl logs nginx-test-858cd7c5cb-52q7x -n testing -c vault-agent
# Clean startup, no errors
```

### Step 7: NFS Mount Test (ROOT CAUSE)

```bash
# Inside broken pod:
kubectl exec nginx-test-858cd7c5cb-52q7x -n testing -- ls /usr/share/nginx/html
# → hangs, Ctrl+C required

# Inside working pod:
kubectl exec nginx-test-858cd7c5cb-d2t65 -n testing -- ls /usr/share/nginx/html
# → index.html (instant)
```

**ROOT CAUSE CONFIRMED:** NFS mount stuck at kernel level.

### Step 8: Verify NFS Mount Options

```bash
# On worker node:
mount | grep nfs
# shows: hard,timeo=600 (kernel defaults)
```

No `mountOptions` in PV → kernel used `hard` mount with 60-second retries forever.

---

## 4. Root Cause

| Factor | Detail |
|--------|--------|
| **PV Definition** | No `mountOptions` field |
| **Kernel Default** | `hard` mount with `timeo=600` (60s retry, forever) |
| **NFS Server** | Brief disruption at 10.0.40.120 |
| **Result** | Workers 2+3 hit the disruption during active I/O → stuck forever |
| **Worker 1** | Not performing I/O at that moment → recovered |

**Hard mount behavior:** Kernel retries NFS operations indefinitely. Nginx process alive, accepting TCP, but any file read blocked forever.

---

## 5. Solution

### Immediate: Rolling Restart

```bash
kubectl rollout restart -n testing deploy/nginx-test
kubectl rollout status -n testing deploy/nginx-test
```

New pods got fresh NFS mounts. All workers responsive immediately.

### Permanent: Add mountOptions to PV/StorageClass

```yaml
mountOptions:
  - soft
  - timeo=30
  - retrans=3
```

| Option | Meaning |
|--------|---------|
| `soft` | Return I/O error after retries (don't hang forever) |
| `timeo=30` | 3-second timeout per retry |
| `retrans=3` | 3 retries before error |

**Result:** Future NFS disruption → Pod returns 500 error → Load balancer routes to healthy pods → Graceful degradation.

### ⚠️ Important: mountOptions on StorageClass vs Static PV

When using static PVs (manual creation), `mountOptions` goes on the PV definition.

When using dynamic provisioning via CSI StorageClass, `mountOptions` must be set on the **StorageClass** — the PV is auto-generated by CSI and inherits mount options from the StorageClass. Setting mountOptions only on a static PV does not affect dynamically provisioned PVs.

```yaml
# Static PV approach (manual)
apiVersion: v1
kind: PersistentVolume
spec:
  mountOptions:
    - soft
    - timeo=30
    - retrans=3

# CSI StorageClass approach (dynamic) — set here instead
apiVersion: storage.k8s.io/v1
kind: StorageClass
mountOptions:
  - soft
  - timeo=30
  - retrans=3
```

### ⚠️ Soft Mount Is NOT Correct for All Workloads

`soft` is correct for stateless, replicated workloads like nginx — crash and restart is acceptable and preferable to hanging.

`soft` is **wrong** for databases. If NFS has a brief disruption during a database write, soft mount returns an I/O error to InnoDB which causes a crash and potential data corruption. Databases must use `hard` mount.

See TS-K8S-007 and TS-K8S-015 for the consequences of soft mount on MariaDB.

### Files Changed

- All PV definitions: Added `mountOptions: [soft, timeo=30, retrans=3]`
- All StorageClass definitions: Added same `mountOptions`
- See TS-K8S-006 for complete NFS storage architecture update

### Prevention Measures

- Always set `mountOptions` for NFS volumes — never rely on kernel defaults
- Use `soft` mount for read-heavy replicated stateless workloads
- Use `hard` + `intr` mount for databases and write-critical stateful workloads
- Use `curl` for reliable testing (browsers mask issues with auto-retry)

---

## 6. Solution Risk

- **Risk Level:** Low
- **Potential Impact:**
  - Rolling restart: Brief service interruption (~30 seconds per pod)
  - Mount options change: Requires PV/StorageClass recreation and pod restart
  - With `soft` mount: Application receives I/O error instead of hanging

---

## 7. Impact After Fix

**Observed Results:**
- All pods responsive immediately after rolling restart
- After mount options applied: Future NFS issues result in 500 errors instead of silent hangs
- Load balancer properly routes traffic away from failing pods

---

## 8. Notes

### Hard vs Soft Mount — Full Decision Table

| Mount Type | Behavior on NFS disruption | Use Case |
|------------|---------------------------|----------|
| `hard` (kernel default) | Retry forever, never fail | Databases, write-heavy stateful apps |
| `soft` | Fail after retries with I/O error | Read-heavy, replicated, stateless apps |
| `hard` + `intr` | Retry forever but allow SIGKILL interrupt | Databases where manual intervention is acceptable |

### Workload Mount Option Reference

| Workload | Recommended | Reason |
|---|---|---|
| Nginx, static file serving | `soft, timeo=30, retrans=3` | Crash + restart better than silent hang |
| WordPress | `soft, timeo=30, retrans=3` | Stateless, replicated, graceful degradation |
| Prometheus, Grafana | `soft, timeo=30, retrans=3` | Can rescrape, should not hang cluster |
| MariaDB, PostgreSQL | `hard, timeo=600, retrans=5, intr` | Data integrity critical — see TS-K8S-007/015 |

### Lessons Learned

| Lesson | Detail |
|--------|--------|
| `Running` status doesn't mean healthy | Pod can accept TCP but hang on I/O |
| Always set `mountOptions` for NFS | Never rely on kernel defaults |
| Test Pod IP directly | Isolates problem from NodePort/kube-proxy/Calico |
| `soft` mount for stateless replicated workloads | Graceful degradation > silent hang |
| `hard` mount for databases | Data integrity > availability |
| Browser masks issues | Use `curl` for reliable testing |
| Check NFS mount with `ls` inside pod | Quickest way to confirm NFS stuck |

### Commands Reference

```bash
# Check Pod Status
kubectl get pods -n <namespace> -o wide
kubectl describe pod <pod-name> -n <namespace>

# Test Pod Connectivity (bypass NodePort/kube-proxy)
curl http://<POD_IP>:<PORT>
curl http://<CLUSTER_IP>:<PORT>
curl http://<NODE_IP>:<NODE_PORT>

# Check NFS Mount Inside Pod
kubectl exec <pod-name> -n <namespace> -- ls /path/to/nfs/mount
kubectl exec <pod-name> -n <namespace> -- cat /proc/mounts | grep nfs

# Check NFS Mount on Worker Node
ssh root@<worker-node>
mount | grep nfs
showmount -e <nfs-server-ip>

# Check Calico BGP
calicoctl node status

# Rolling Restart
kubectl rollout restart -n <namespace> deploy/<deployment-name>
kubectl rollout status -n <namespace> deploy/<deployment-name>
```

---

## 9. Workaround

**Immediate:** Rolling restart to get fresh NFS mounts:
```bash
kubectl rollout restart -n <namespace> deploy/<deployment-name>
```

This clears the stuck NFS mount by creating new pods with fresh mounts. Does not prevent recurrence — must apply permanent fix with `mountOptions`.