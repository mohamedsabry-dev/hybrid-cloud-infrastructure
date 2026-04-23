# TS-K8S-003 | 2026-03-31 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / NFS Storage / Pod Health
Sub-techs: NFS mount options, hard vs soft mount, PersistentVolume, nginx,
           Vault sidecar, external NGINX reverse proxy
Environment: DEV k8s cluster | 3 workers | NFS server 10.0.40.120
Discovered during: External NGINX reverse proxy load-balancing test
Related: TS-K8S-006 (NFS storage guide), TS-K8S-007 (soft mount broke MariaDB),
         TS-K8S-015 (stale NFS mount on CSI restart)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Pods with NFS-backed volumes intermittently hung and stopped serving traffic. Nginx
accepted TCP connections but never responded with HTTP. The external NGINX reverse
proxy (load-balancing across 3 workers on NodePort 30080) showed retries across
backends:

```
192.168.100.223 - [31/Mar/2026:20:14:26] "GET / HTTP/1.1" 200 upstream: 10.0.64.10:30080, 10.0.64.11:30080
```
Two workers in one line = retry happened.

All three tried, client gave up:
```
192.168.100.223 - [31/Mar/2026:20:17:45] "GET / HTTP/1.1" 499 upstream: 10.0.64.12:30080, 10.0.64.11:30080, 10.0.64.10:30080
```

Browser masked the issue with auto-retry. `curl` exposed the hang clearly.

_____________________________________________________________________

[Analysis]

# Step 1: Rule out network

```
ping 10.0.64.10  → 0% packet loss, ~2.9ms
ping 10.0.64.11  → 0% packet loss, ~3.0ms
ping 10.0.64.12  → 0% packet loss, ~3.0ms
```

Network fine. Calico BGP also fine — `calicoctl node status` showed all peers Established.

# Step 2: NodePort test — TCP connects, HTTP hangs

```
curl http://10.0.64.10:30080  → hangs
curl http://10.0.64.11:30080  → hangs intermittently
curl http://10.0.64.12:30080  → hangs intermittently
```

TCP layer works, HTTP doesn't. Problem above TCP.

# Step 3: ClusterIP test — same hang

```
curl http://10.96.229.52:8080  → Hello from NFS! (first time)
curl http://10.96.229.52:8080  → hangs (second)
curl http://10.96.229.52:8080  → hangs (third)
```

ClusterIP itself hung intermittently. Not a NodePort or kube-proxy issue — problem
is at pod level.

# Step 4: Direct pod IP test — isolated the broken pods

Command: kubectl get pods -n testing -o wide

```
nginx-test-858cd7c5cb-52q7x  2/2  Running  k8s-worker3  10.244.29.154
nginx-test-858cd7c5cb-7vmzj  2/2  Running  k8s-worker2  10.244.207.88
nginx-test-858cd7c5cb-d2t65  2/2  Running  k8s-worker1  10.244.62.54
```

```
curl http://10.244.62.54:80   → Hello from NFS!  (worker1 — healthy)
curl http://10.244.207.88:80  → hangs             (worker2 — stuck)
curl http://10.244.29.154:80  → hangs             (worker3 — stuck)
```

Two pods stuck, one healthy. All showing `Running 2/2`. Status lied.

# Step 5: Container logs — clean, no errors

```
kubectl logs nginx-test-858cd7c5cb-52q7x -n testing -c nginx    → clean
kubectl logs nginx-test-858cd7c5cb-52q7x -n testing -c vault-agent → clean
```

# Step 6: NFS mount test — found the root cause

```
# Inside broken pod:
kubectl exec nginx-test-858cd7c5cb-52q7x -n testing -- ls /usr/share/nginx/html
→ hangs, Ctrl+C required

# Inside working pod:
kubectl exec nginx-test-858cd7c5cb-d2t65 -n testing -- ls /usr/share/nginx/html
→ index.html (instant)
```

NFS mount stuck at kernel level. The `ls` hanging inside the pod confirmed it.

# Step 7: Check mount options on worker

```
mount | grep nfs
→ shows: hard,timeo=600 (kernel defaults)
```

No `mountOptions` in the PV definition — kernel used `hard` mount with 60-second
retries forever. That's the problem.

_____________________________________________________________________

[Final Root Cause]
The PV had no `mountOptions` set, so the kernel used defaults: `hard` mount with
`timeo=600` (60-second retry, indefinitely). When the NFS server at 10.0.40.120
had a brief disruption, workers 2 and 3 were performing active I/O at that moment
and their NFS mounts got stuck in kernel-level retry loops forever. Worker 1 wasn't
doing I/O at that instant and recovered.

Hard mount behavior: kernel retries NFS operations indefinitely. The nginx process
stays alive, accepts TCP connections, but any file read (serving the HTML from NFS)
blocks forever. Pod shows `Running 2/2` but is completely unresponsive.

_____________________________________________________________________

[Final Solution]

# Immediate: rolling restart for fresh NFS mounts

```
kubectl rollout restart -n testing deploy/nginx-test
kubectl rollout status -n testing deploy/nginx-test
```

New pods got fresh mounts. All workers responsive immediately.

# Permanent: add mountOptions to PV/StorageClass

```yaml
mountOptions:
  - soft
  - timeo=30
  - retrans=3
```

  soft     = return I/O error after retries (don't hang forever)
  timeo=30 = 3-second timeout per retry
  retrans=3 = 3 retries before returning error

With this, future NFS disruptions cause a 500 error instead of a silent hang.
Load balancer routes traffic to healthy pods. Graceful degradation.

Important: `mountOptions` goes on the StorageClass for dynamic provisioning (CSI
auto-generates PVs from it), or directly on the PV for static volumes.

# Warning: soft mount is NOT correct for databases

`soft` works for stateless replicated workloads like nginx — crash and restart is
preferable to hanging forever.

`soft` is wrong for databases. A brief NFS disruption during a write returns an
I/O error to InnoDB, which crashes and risks data corruption. Databases must use
`hard` mount. See TS-K8S-007 and TS-K8S-015 for what happens when you get this wrong.

Verified: Yes — all pods responsive, future NFS disruptions degrade gracefully.

_____________________________________________________________________

[Risk Level] LOW

Rolling restart causes ~30s interruption per pod. The mount options change requires
PV/StorageClass recreation and pod restart, but the tradeoff (I/O error vs infinite
hang) is clearly worth it for stateless workloads.

_____________________________________________________________________

[References]
- TS-K8S-006 — complete NFS storage architecture guide (updated from this case)
- TS-K8S-007 — InnoDB + soft mount = crash (the opposite tradeoff)
- TS-K8S-015 — stale NFS mount on CSI restart caused MariaDB CrashLoopBackOff
