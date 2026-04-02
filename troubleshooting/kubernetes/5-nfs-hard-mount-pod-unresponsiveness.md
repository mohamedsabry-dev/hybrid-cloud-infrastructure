# Case 5: NFS Hard Mount Causing Intermittent Pod Unresponsiveness

## Status: RESOLVED
## Date: 2026-03-31
## Severity: High
## Environment: k8s-dev cluster (bare-metal kubeadm, 3 workers, Calico CNI, NFS storage, Vault sidecar)
## Related: Case 3-4 (NFS Storage), Case 6 (Complete NFS Storage Guide)

---

## 1. Issue Summary

Pods with NFS-backed volumes intermittently hung and stopped serving traffic. Nginx accepted TCP connections but never responded with HTTP. Root cause: NFS `hard` mount (kernel default) caused infinite blocking when NFS server had transient issues.

---

## 2. What Was Being Tested

External NGINX reverse proxy (LXC container) load-balancing across three K8s workers on NodePort 30080. Backend: nginx deployment with 3 replicas serving static file from NFS PersistentVolume.

```nginx
upstream k8s_workers {
    least_conn;
    server 10.0.64.10:30080;
    server 10.0.64.11:30080;
    server 10.0.64.12:30080;
}
```

---

## 3. How Issue Was Discovered

### NGINX upstream log showed retries across workers:

```
192.168.100.223 - [31/Mar/2026:20:14:26] "GET / HTTP/1.1" 200 upstream: 10.0.64.10:30080, 10.0.64.11:30080
```
Two workers in one line = retry happened.

### All three workers tried, client gave up (499):

```
192.168.100.223 - [31/Mar/2026:20:17:45] "GET / HTTP/1.1" 499 upstream: 10.0.64.12:30080, 10.0.64.11:30080, 10.0.64.10:30080
```

Browser masked the issue (auto-retry). `curl` exposed the hang clearly.

---

## 4. Investigation Steps

### 4.1 Network Connectivity (Ruled Out)

```bash
ping 10.0.64.10  # 0% packet loss, ~2.9ms
ping 10.0.64.11  # 0% packet loss, ~3.0ms
ping 10.0.64.12  # 0% packet loss, ~3.0ms
```

### 4.2 NodePort Test (TCP connects, HTTP hangs)

```bash
curl http://10.0.64.10:30080  # hangs
curl http://10.0.64.11:30080  # hangs intermittently
curl http://10.0.64.12:30080  # hangs intermittently
```

TCP connected but no HTTP response. Problem above TCP layer.

### 4.3 Calico BGP (Ruled Out)

```bash
calicoctl node status
# All peers: up | Established
```

### 4.4 ClusterIP Test (Critical Finding)

```bash
curl http://10.96.229.52:8080  # Hello from NFS! (first)
curl http://10.96.229.52:8080  # hangs (second)
curl http://10.96.229.52:8080  # hangs (third)
```

ClusterIP itself hung intermittently. Problem at Pod level, not NGINX/NodePort/Calico.

### 4.5 Pod IP Direct Test (Isolation)

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

### 4.6 Container Logs (Clean)

```bash
kubectl logs nginx-test-858cd7c5cb-52q7x -n testing -c nginx
kubectl logs nginx-test-858cd7c5cb-52q7x -n testing -c vault-agent
# Clean startup, no errors
```

### 4.7 NFS Mount Test (ROOT CAUSE)

```bash
# Inside broken pod:
kubectl exec nginx-test-858cd7c5cb-52q7x -n testing -- ls /usr/share/nginx/html
# → hangs, Ctrl+C required

# Inside working pod:
kubectl exec nginx-test-858cd7c5cb-d2t65 -n testing -- ls /usr/share/nginx/html
# → index.html (instant)
```

**ROOT CAUSE CONFIRMED:** NFS mount stuck at kernel level.

### 4.8 Verify NFS Mount Options

```bash
# On worker node:
mount | grep nfs
# shows: hard,timeo=600 (kernel defaults)
```

No `mountOptions` in PV → kernel used `hard` mount with 60-second retries forever.

---

## 5. Root Cause Analysis

| Factor | Detail |
|--------|--------|
| **PV Definition** | No `mountOptions` field |
| **Kernel Default** | `hard` mount with `timeo=600` (60s retry, forever) |
| **NFS Server** | Brief disruption at 10.0.40.120 |
| **Result** | Workers 2+3 hit the disruption during active I/O → stuck forever |
| **Worker 1** | Not performing I/O at that moment → recovered |

**Hard mount behavior:** Kernel retries NFS operations indefinitely. Nginx process alive, accepting TCP, but any file read blocked forever.

---

## 6. Resolution

### 6.1 Immediate: Rolling Restart

```bash
kubectl rollout restart -n testing deploy/nginx-test
kubectl rollout status -n testing deploy/nginx-test
```

New pods got fresh NFS mounts. All workers responsive immediately.

### 6.2 Permanent: Add mountOptions to PV/StorageClass

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

---

## 7. Hard vs Soft Mount Tradeoff

| Mount Type | Behavior | Use Case |
|------------|----------|----------|
| `hard` | Retry forever, never fail | Databases, write-heavy stateful apps |
| `soft` | Fail after retries with I/O error | Read-heavy, replicated, stateless apps |

For this use case (nginx reading static files, 3 replicas), `soft` is correct. Silent hang is worse than 500 error.

---

## 8. Commands Reference

### Check Pod Status
```bash
kubectl get pods -n <namespace> -o wide
kubectl describe pod <pod-name> -n <namespace>
```

### Test Pod Connectivity
```bash
# Direct to Pod IP (bypass NodePort/kube-proxy)
curl http://<POD_IP>:<PORT>

# To ClusterIP
curl http://<CLUSTER_IP>:<PORT>

# To NodePort
curl http://<NODE_IP>:<NODE_PORT>
```

### Check NFS Mount Inside Pod
```bash
kubectl exec <pod-name> -n <namespace> -- ls /path/to/nfs/mount
kubectl exec <pod-name> -n <namespace> -- cat /proc/mounts | grep nfs
```

### Check NFS Mount on Worker Node
```bash
ssh root@<worker-node>
mount | grep nfs
showmount -e <nfs-server-ip>
```

### Check Calico BGP
```bash
calicoctl node status
```

### Rolling Restart
```bash
kubectl rollout restart -n <namespace> deploy/<deployment-name>
kubectl rollout status -n <namespace> deploy/<deployment-name>
```

### Check Container Logs
```bash
kubectl logs <pod-name> -n <namespace> -c <container-name>
kubectl logs <pod-name> -n <namespace> --all-containers
```

### Check Process Inside Pod
```bash
kubectl exec <pod-name> -n <namespace> -- cat /proc/1/status
kubectl exec <pod-name> -n <namespace> -- ps aux
```

---

## 9. Key Takeaways

| Lesson | Detail |
|--------|--------|
| `Running` status doesn't mean healthy | Pod can accept TCP but hang on I/O |
| Always set `mountOptions` for NFS | Never rely on kernel defaults |
| Test Pod IP directly | Isolates problem from NodePort/kube-proxy/Calico |
| `soft` mount for read-heavy replicated workloads | Graceful degradation > silent hang |
| Browser masks issues | Use `curl` for reliable testing |
| Check NFS mount with `ls` inside pod | Quickest way to confirm NFS stuck |

---

## 10. Files Changed

- All PV definitions: Added `mountOptions: [soft, timeo=30, retrans=3]`
- All StorageClass definitions: Added same `mountOptions`
- See Case 6 for complete NFS storage architecture update
