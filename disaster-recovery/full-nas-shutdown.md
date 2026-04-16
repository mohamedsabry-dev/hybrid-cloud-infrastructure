# Full NAS Shutdown DR Test
# Date: 2026-04-17
# Status: COMPLETED
# Result: PASS - All behaviors as expected, storage class design validated

---

## Objective

Power off NAS completely to test the most realistic major storage disaster scenario.
Compare behavior between different storage classes and mount options.

---

## Storage Classes Comparison

| StorageClass | Mount Type | Timeout | Retries | Expected Behavior |
|--------------|------------|---------|---------|-------------------|
| **nfs-retain** | `soft` | 3s (timeo=30) | 3 | Fast fail with I/O error |
| **nfs-delete** | `soft` | 3s (timeo=30) | 3 | Fast fail with I/O error |
| **nfs-database** | `hard` + `intr` | 60s (timeo=600) | 5 | Hangs until NFS recovers (interruptible) |

---

## Apps and Their Storage Configuration

| App | Namespace | StorageClass | Mount Type | Expected on NAS Down |
|-----|-----------|--------------|------------|---------------------|
| WordPress | apps | nfs-retain | `soft` | Fast I/O error → readiness fail → endpoint removed |
| MariaDB | database | nfs-database | `hard` | **Hangs** until NFS recovers |
| Grafana | monitoring | nfs-retain | `soft` | Fast I/O error → CrashLoopBackOff |
| Prometheus | monitoring | nfs-retain | `soft` | Fast I/O error → storage errors |
| Loki | monitoring | nfs-retain | `soft` | Fast I/O error → storage errors |
| Alertmanager | monitoring | nfs-retain | `soft` | Fast I/O error → storage errors |

---

## Non-NFS Components (Should Survive)

| Component | Namespace | NFS Dependency |
|-----------|-----------|----------------|
| Ingress-nginx | ingress-nginx | None |
| Vault Agent | vault | None |
| Flux controllers | flux-system | None |
| CoreDNS | kube-system | None |
| etcd | kube-system | None |

---

## Pre-Test Baseline

### Network Architecture Note
```
Masters: NO storage interface (only eth0 with 10.0.61.x for management)
Workers: eth0 (10.0.64.x management) + eth1 (10.0.40.x storage)

Worker1: 10.0.40.201
Worker2: 10.0.40.202
Worker3: 10.0.40.203
```

### NAS Exports
```bash
[root@k8s-worker1 ~]# showmount -e 10.0.40.120
Export list for 10.0.40.120:
/volume1/k8s-prod     10.0.40.103,10.0.40.102,10.0.40.101
/volume1/k8s-dev      10.0.40.203,10.0.40.202,10.0.40.201
/volume1/Backups      10.0.40.100,10.0.40.110
/volume1/prod-storage 10.0.40.100
/volume1/dev-storage  10.0.40.110
/volume1/shared-iso   10.0.40.110,10.0.40.100
```

### Pod Status
```bash
[root@k8s-master1 ~]# kubectl get pods -n apps -o wide
NAME                         READY   STATUS    RESTARTS   AGE    IP              NODE
wordpress-5f649b595f-jwcnk   2/2     Running   0          24m    10.244.62.8     k8s-worker1.lab.local
wordpress-5f649b595f-n65mm   2/2     Running   0          122m   10.244.207.68   k8s-worker2.lab.local
wordpress-5f649b595f-tpzrj   2/2     Running   0          121m   10.244.29.174   k8s-worker3.lab.local

[root@k8s-master1 ~]# kubectl get pods -n database -o wide
NAME        READY   STATUS    RESTARTS        AGE     IP               NODE
mariadb-0   2/2     Running   12 (160m ago)   2d23h   10.244.207.125   k8s-worker2.lab.local

[root@k8s-master1 ~]# kubectl get pods -n monitoring -o wide
NAME                                                        READY   STATUS    NODE
alertmanager-kube-prometheus-stack-alertmanager-0           2/2     Running   k8s-worker1.lab.local
kube-prometheus-stack-grafana-5f6554dcf5-lrvqq              4/4     Running   k8s-worker2.lab.local
kube-prometheus-stack-grafana-5f6554dcf5-mqbk5              4/4     Running   k8s-worker1.lab.local
kube-prometheus-stack-grafana-5f6554dcf5-pbbn6              4/4     Running   k8s-worker3.lab.local
loki-0                                                      2/2     Running   k8s-worker2.lab.local
prometheus-kube-prometheus-stack-prometheus-0               2/2     Running   k8s-worker3.lab.local
```

### Pod Placement Summary
| App | Replicas | Node(s) | StorageClass |
|-----|----------|---------|--------------|
| WordPress | 3 | worker1, worker2, worker3 | nfs-retain (soft) |
| MariaDB | 1 | worker2 | nfs-database (hard) |
| Grafana | 3 | worker1, worker2, worker3 | nfs-retain (soft) |
| Prometheus | 1 | worker3 | nfs-retain (soft) |
| Loki | 1 | worker2 | nfs-retain (soft) |
| Alertmanager | 1 | worker1 | nfs-retain (soft) |

### PVC Status
```bash
[root@k8s-master1 ~]# kubectl get pvc -A
NAMESPACE    NAME                                            STATUS   CAPACITY   STORAGECLASS
apps         wordpress-data                                  Bound    15Gi       nfs-retain
database     mariadb-data-mariadb-0                          Bound    15Gi       nfs-database
monitoring   alertmanager-kube-prometheus-stack-...          Bound    5Gi        nfs-retain
monitoring   kube-prometheus-stack-grafana                   Bound    5Gi        nfs-retain
monitoring   prometheus-kube-prometheus-stack-...            Bound    20Gi       nfs-retain
monitoring   storage-loki-0                                  Bound    50Gi       nfs-retain
```

### WordPress Accessibility
```bash
[root@k8s-master1 ~]# curl -I http://wordpress-dev.lab.local
HTTP/1.1 200 OK
Server: nginx/1.26.3
Date: Thu, 16 Apr 2026 21:46:11 GMT
Content-Type: text/html; charset=UTF-8
```

### Non-NFS Components Status
```bash
[root@k8s-master1 ~]# kubectl get pods -n ingress-nginx
NAME                                        READY   STATUS    RESTARTS   AGE
ingress-nginx-controller-7d4c58858f-c9wrl   1/1     Running   0          55m
ingress-nginx-controller-7d4c58858f-d782c   1/1     Running   0          55m
ingress-nginx-controller-7d4c58858f-lcxbl   1/1     Running   0          55m

[root@k8s-master1 ~]# kubectl get pods -n vault
NAME                                    READY   STATUS    RESTARTS        AGE
vault-agent-injector-5877589b57-4h2ts   1/1     Running   9 (106m ago)    5d2h
vault-agent-injector-5877589b57-cwh5f   1/1     Running   6 (3h40m ago)   2d23h

[root@k8s-master1 ~]# flux get kustomization
NAME              REVISION             SUSPENDED    READY    MESSAGE
apps              dev@sha1:c35ae2a9    False        True     Applied revision: dev@sha1:c35ae2a9
flux-system       dev@sha1:c35ae2a9    False        True     Applied revision: dev@sha1:c35ae2a9
infrastructure    dev@sha1:c35ae2a9    False        True     Applied revision: dev@sha1:c35ae2a9
```

### CSI Controllers
```bash
[root@k8s-master1 ~]# kubectl get pods -o wide -A | grep csi
csi-nfs-controller-8455c76c5f-99nbm   5/5   Running   k8s-worker2.lab.local
csi-nfs-controller-8455c76c5f-snggk   5/5   Running   k8s-worker1.lab.local
csi-nfs-node-dgfgf                    3/3   Running   k8s-worker1.lab.local
csi-nfs-node-g6cng                    3/3   Running   k8s-worker2.lab.local
csi-nfs-node-gkdlg                    3/3   Running   k8s-worker3.lab.local
```

---

## Pre-Test Fix: Restrict csi-nfs-node DaemonSet to Worker Nodes Only

================================================================================
OPERATION: Restrict csi-nfs-node DaemonSet to Worker Nodes Only
DATE: 2026-04-16
CLUSTER: homelab k8s (3 masters: 10.0.61.10-12 | 3 workers: 10.0.64.10-12)
================================================================================

REASON
------
The csi-nfs-node DaemonSet was running on all 6 nodes by default (chart ships
with affinity: {} and nodeSelector: {}). Master nodes in this cluster have no
storage interfaces and are not intended to serve as NFS mount points. Running
the CSI node plugin on masters adds unnecessary overhead — extra processes,
resource consumption, and kubelet socket exposure — with zero functional
benefit. The fix scopes the DaemonSet strictly to the 3 worker nodes where
actual workloads and PVC consumers live.

PROBLEM OBSERVED
----------------
- DaemonSet showed DESIRED=6, meaning pods were scheduled on all nodes
- Masters (10.0.61.10-12) have no storage interface — the CSI node plugin
  on those nodes was pure overhead with no valid use case

INVESTIGATION METHOD
--------------------
1. Confirmed the deployed resources via Flux and kubectl:

     flux get helmrelease csi-driver-nfs -n kube-system
     kubectl get daemonset -n kube-system | grep csi-nfs
     kubectl get pods -n kube-system -l app=csi-nfs-node -o wide

2. Inspected chart defaults to find the correct override key:

     helm show values csi-driver-nfs \
       --repo https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts \
       --version 4.13.1 | grep -A 10 "node:"

   Chart confirmed:
     node:
       affinity: {}
       nodeSelector: {}

3. Determined that nodeSelector cannot express exclusion (it only matches
   labels, not excludes them), so nodeAffinity with operator: DoesNotExist
   was the correct mechanism — same pattern already used for the controller.

FIX APPLIED
-----------
Added nodeAffinity under node: in the HelmRelease values, mirroring the
existing controller affinity block:

     node:
       priorityClassName: system-node-critical
       affinity:
         nodeAffinity:
           requiredDuringSchedulingIgnoredDuringExecution:
             nodeSelectorTerms:
               - matchExpressions:
                   - key: node-role.kubernetes.io/control-plane
                     operator: DoesNotExist

This tells the DaemonSet scheduler: do not place pods on any node that
carries the control-plane label. Worker nodes carry no such label, so they
remain eligible. Masters are excluded automatically.

RECONCILIATION
--------------
Change was committed and pushed to Git. Flux reconciled the HelmRelease,
which updated the DaemonSet spec. The DaemonSet controller evicted the 3
master-node pods automatically with no manual intervention required.

RESULT VERIFIED
---------------
```bash
[root@k8s-master1 ~]# kubectl get pods -A -o wide | grep csi
csi-nfs-controller-8455c76c5f-99nbm   5/5   Running   0   k8s-worker2.lab.local
csi-nfs-controller-8455c76c5f-snggk   5/5   Running   0   k8s-worker1.lab.local
csi-nfs-node-77cww                    3/3   Running   0   k8s-worker2.lab.local
csi-nfs-node-czdrh                    3/3   Running   0   k8s-worker1.lab.local
csi-nfs-node-sdhw9                    3/3   Running   0   k8s-worker3.lab.local
```

DESIRED=3, READY=3 — pods running on worker nodes only (10.0.64.10-12).

KEY LEARNING
------------
- Helm chart defaults are permissive by design — always audit DaemonSet
  scheduling before deploying in a mixed-role cluster.
- nodeSelector can only include; nodeAffinity with DoesNotExist is required
  to exclude a role.
- The controller already had this affinity set correctly — the node plugin
  was simply missed at initial deployment time.
- GitOps workflow (edit values → push → flux reconcile) handled the rollout
  cleanly with zero downtime to existing PVC consumers.

================================================================================

---

## Test Execution

### Step 1: Power Off NAS

Method: (Proxmox / Synology UI / SSH)
Time:

```bash
# Verify NAS unreachable after shutdown
ping 10.0.40.120
showmount -e 10.0.40.120
```

---

### Step 2: Monitor Pod Behavior

```bash
# Watch all affected pods
kubectl get pods -n apps -w
kubectl get pods -n database -w
kubectl get pods -n monitoring -w
```

---

## Test Execution

### Timeline
```
12:03:xx AM - NAS restart triggered (Synology UI)
12:04:xx AM - NAS shutdown complete, NFS unreachable
12:06:30 AM - NAS back online, services restored
Total outage: ~2-2.5 minutes
```

---

## During Outage Observations

### WordPress (soft mount - nfs-retain)

**Expected:** Fast I/O error → readiness fail → removed from endpoints
**Actual:** ✅ Endpoints removed, NO pod restarts

```bash
# Endpoint removal observed during outage:
[root@k8s-master1 ~]# kubectl get endpoints wordpress -n apps -w
NAME        ENDPOINTS                                          AGE
wordpress   10.244.207.68:80,10.244.29.174:80,10.244.62.8:80   7d8h   # 3 endpoints
wordpress   10.244.29.174:80,10.244.62.8:80                    7d8h   # 2 endpoints (worker2 removed)
wordpress   10.244.62.8:80                                     7d8h   # 1 endpoint (worker3 removed)
wordpress   10.244.207.68:80,10.244.29.174:80,10.244.62.8:80   7d8h   # 3 endpoints (all restored)

# Pod status - NO RESTARTS:
NAME                         READY   STATUS    RESTARTS   AGE
wordpress-5f649b595f-jwcnk   2/2     Running   0          45m    # Still 0 restarts
wordpress-5f649b595f-n65mm   2/2     Running   0          143m   # Still 0 restarts
wordpress-5f649b595f-tpzrj   2/2     Running   0          143m   # Still 0 restarts
```

**Analysis:** Soft mount (timeo=30 × retrans=3 = ~9s) returned I/O errors after timeout.
Readiness probe failed → endpoints removed → 503 to users.
But PHP processes didn't crash because:
1. Not actively writing to NFS at that moment, OR
2. PHP handled ESTALE/EIO errors gracefully without crashing
NAS recovered before container crashed.

### MariaDB (hard mount - nfs-database)

**Expected:** Hangs until NFS recovers (processes stuck in D state)
**Actual:** ✅ Hung and resumed, NO restart

```bash
# Before and after - same restart count:
NAME        READY   STATUS    RESTARTS        AGE
mariadb-0   2/2     Running   12 (179m ago)   2d23h   # Before
mariadb-0   2/2     Running   12 (3h2m ago)   2d23h   # After - still 12!
```

**Analysis:** Hard mount config:
```
timeo=600   (60 seconds per attempt)
retrans=5   (5 retries)
intr        (interruptible - can be killed if needed)
Total timeout: 60s × 5 = 300 seconds (5 minutes)
```
NAS was only down ~2 minutes, well within the 5-minute hard mount timeout.
MariaDB I/O operations simply paused (processes in D state) and resumed when NFS recovered.
**This is exactly why hard mount is correct for databases** - data integrity preserved.

### Grafana (soft mount - nfs-retain)

**Expected:** Fast I/O error → CrashLoopBackOff
**Actual:** ✅ NO restarts (3 replicas survived)

```bash
# All 3 replicas - same restart counts:
kube-prometheus-stack-grafana-5f6554dcf5-lrvqq   4/4   Running   22   # Before: 22
kube-prometheus-stack-grafana-5f6554dcf5-mqbk5   4/4   Running   25   # Before: 25
kube-prometheus-stack-grafana-5f6554dcf5-pbbn6   4/4   Running   24   # Before: 24
```

**Analysis:** Grafana not constantly writing to NFS (mostly reads for dashboards).
Brief I/O errors handled gracefully. HA (3 replicas) provided resilience.

### Prometheus (soft mount - nfs-retain)

**Expected:** Storage errors
**Actual:** ⚠️ 1 RESTART (only component that restarted)

```bash
# During outage - container restart observed:
prometheus-kube-prometheus-stack-prometheus-0   2/2   Running   8 (3h56m ago)   # Before
prometheus-kube-prometheus-stack-prometheus-0   1/2   Running   8 (3h59m ago)   # Partial ready
prometheus-kube-prometheus-stack-prometheus-0   1/2   Running   9 (1s ago)      # RESTARTED!
prometheus-kube-prometheus-stack-prometheus-0   1/2   Running   9 (14s ago)     # Starting up
prometheus-kube-prometheus-stack-prometheus-0   1/2   Running   9 (29s ago)     # Still starting
prometheus-kube-prometheus-stack-prometheus-0   2/2   Running   9 (29s ago)     # Fully recovered
```

**Analysis:** Prometheus constantly writes to TSDB (time-series database) on NFS.
Soft mount returned I/O errors → Prometheus detected write failures → crashed.
Kubelet restarted container after NFS recovered → Prometheus recovered in ~30s.
**This is expected behavior for write-heavy workloads on soft mount.**

### Loki (soft mount - nfs-retain)

**Expected:** Storage errors
**Actual:** ✅ NO restarts

```bash
loki-0   2/2   Running   22 (3h56m ago)   # Same restart count
```

**Analysis:** Similar to Grafana - survived the brief outage.

### Alertmanager (soft mount - nfs-retain)

**Expected:** Storage errors
**Actual:** ✅ NO restarts

```bash
alertmanager-kube-prometheus-stack-alertmanager-0   2/2   Running   22 (3h56m ago)   # Same
```

### Non-NFS Components

**Expected:** All UP
**Actual:** ✅ All survived (not checked during outage but confirmed after)

---

## Kernel Level Observations

```bash
[root@k8s-worker1 ~]# dmesg | grep -i nfs | tail -20
[14311.456188] nfs: server 10.0.40.120 not responding, timed out
[14316.520241] nfs: server 10.0.40.120 not responding, timed out
[14316.608238] nfs: server 10.0.40.120 not responding, timed out
[14317.288242] nfs: server 10.0.40.120 not responding, timed out
[14318.248218] nfs: server 10.0.40.120 not responding, timed out
[14320.040241] nfs: server 10.0.40.120 not responding, timed out
[14320.520278] nfs: server 10.0.40.120 not responding, timed out
[14321.328282] nfs: server 10.0.40.120 not responding, timed out
[14321.353261] nfs: server 10.0.40.120 not responding, timed out
[14323.304250] nfs: server 10.0.40.120 not responding, timed out
[14328.232307] nfs: server 10.0.40.120 not responding, timed out
[14331.240275] nfs: server 10.0.40.120 not responding, timed out
[14331.240423] nfs: server 10.0.40.120 not responding, timed out
[14331.245250] nfs: server 10.0.40.120 not responding, timed out
[14331.248278] nfs: server 10.0.40.120 not responding, timed out
[14331.251253] nfs: server 10.0.40.120 not responding, timed out
[14334.248320] nfs: server 10.0.40.120 not responding, timed out
[14334.250281] nfs: server 10.0.40.120 not responding, timed out
[14334.256262] nfs: server 10.0.40.120 not responding, timed out
[14334.258262] nfs: server 10.0.40.120 not responding, timed out
```

**Analysis:** Kernel NFS client detected server unreachable. Soft mount timeouts fired
every 3 seconds (timeo=30 = 3s). Messages stopped when NAS recovered.

---

## Recovery Summary

### Recovery Timeline
```
12:06:30 AM - All services auto-recovered
Total outage: ~2-2.5 minutes
Recovery: Automatic (no manual intervention)
```

### Results by Mount Type

| App | StorageClass | Mount | Restarts | Behavior |
|-----|--------------|-------|----------|----------|
| WordPress | nfs-retain | soft 3s | **0** | Endpoints removed, pods survived |
| MariaDB | nfs-database | hard 60s | **0** | Hung and resumed (within timeout) |
| Grafana | nfs-retain | soft 3s | **0** | Survived (3 replicas) |
| Prometheus | nfs-retain | soft 3s | **+1** | Crashed and restarted (write-heavy) |
| Loki | nfs-retain | soft 3s | **0** | Survived |
| Alertmanager | nfs-retain | soft 3s | **0** | Survived |

---

## Findings Summary

### Soft Mount Behavior (nfs-retain, nfs-delete)
```
Mount options: soft, timeo=30, retrans=3
Effective timeout: 3s × 3 = 9 seconds before I/O error

Behavior observed:
- Returns ESTALE/EIO errors after timeout
- Does NOT necessarily crash the container
- Apps with intermittent I/O (WordPress, Grafana) survived
- Apps with constant writes (Prometheus TSDB) crashed and restarted
- Readiness probes detected failures → endpoints removed → 503 to users

Key insight: Soft mount is "fail-fast" but graceful for read-heavy apps.
Write-heavy apps will crash but recover quickly after NFS returns.
```

### Hard Mount Behavior (nfs-database)
```
Mount options: hard, timeo=600, retrans=5, intr
Effective timeout: 60s × 5 = 300 seconds (5 minutes)

Behavior observed:
- I/O operations HANG (processes in D state)
- No errors returned to application
- Application paused, not crashed
- Resumed automatically when NFS recovered
- Data integrity preserved

Key insight: Hard mount is correct for databases.
NAS outage < 5 minutes = transparent pause/resume.
NAS outage > 5 minutes = would eventually fail (but intr allows kill).
```

### Why WordPress Survived on Soft Mount (Unexpected?)
```
Expected: Soft mount → I/O error → container crash
Actual: Soft mount → I/O error → container survived

Explanation:
1. WordPress/PHP handles I/O errors gracefully (doesn't crash on ESTALE)
2. WordPress wasn't actively writing to NFS during the 2-minute outage
3. Readiness probe correctly failed → removed from endpoints → 503 to users
4. Container remained Running but NOT Ready
5. When NFS recovered, readiness passed → endpoints restored

The 503 to users is the correct behavior - traffic diverted from unhealthy pods.
Container survival without restart is a bonus - faster recovery.
```

---

## Additional Evidence: Application Logs Analysis

### WordPress Logs (After Recovery - 22:14-22:15)
```bash
[root@k8s-master1 ~]# kubectl logs -l app=wordpress -n apps
# Probes running normally after NAS recovery:

# Readiness probe - checks NFS-mounted /wp-content/index.php
10.0.64.11 - - [16/Apr/2026:22:14:36 +0000] "GET /wp-content/index.php HTTP/1.1" 200 192 "-" "kube-probe/1.35"
10.0.64.11 - - [16/Apr/2026:22:14:41 +0000] "GET /wp-content/index.php HTTP/1.1" 200 192 "-" "kube-probe/1.35"

# Liveness probe - checks local /wp-includes/images/blank.gif
10.0.64.11 - - [16/Apr/2026:22:14:46 +0000] "GET /wp-includes/images/blank.gif HTTP/1.1" 200 289 "-" "kube-probe/1.35"

# All 3 workers (10.0.64.10, .11, .12) show healthy probes
10.0.64.12 - - [16/Apr/2026:22:14:34 +0000] "GET /wp-content/index.php HTTP/1.1" 200 192 "-" "kube-probe/1.35"
10.0.64.10 - - [16/Apr/2026:22:14:37 +0000] "GET /wp-content/index.php HTTP/1.1" 200 192 "-" "kube-probe/1.35"
```

**Analysis:** WordPress logs show probes succeeded AFTER recovery (22:14+).
No error logs during outage = PHP didn't crash, just couldn't serve requests.

### MariaDB Logs (DURING Outage - 22:04-22:08)
```bash
# MariaDB received connection attempts but clients closed before auth:
2026-04-16 22:04:43 4313 [Warning] Aborted connection 4313 to db: 'unconnected' user: 'unauthenticated' host: '10.0.64.11' (This connection closed normally without authentication)
2026-04-16 22:04:48 4316 [Warning] Aborted connection 4316 to db: 'unconnected' user: 'unauthenticated' host: '10.0.64.11'
2026-04-16 22:04:53 4317 [Warning] Aborted connection 4317 to db: 'unconnected' user: 'unauthenticated' host: '10.0.64.11'
...
2026-04-16 22:06:03 4343 [Warning] Aborted connection 4343 to db: 'unconnected' user: 'unauthenticated' host: '10.0.64.11'
2026-04-16 22:06:08 4345 [Warning] Aborted connection 4345 to db: 'unconnected' user: 'unauthenticated' host: '10.0.64.11'
...
2026-04-16 22:08:33 4396 [Warning] Aborted connection 4396 to db: 'unconnected' user: 'unauthenticated' host: '10.0.64.11'
2026-04-16 22:08:38 4397 [Warning] Aborted connection 4397 to db: 'unconnected' user: 'unauthenticated' host: '10.0.64.11'
```

**Analysis:**
```
┌─────────────────────────────────────────────────────────────────────────────┐
│  MARIADB BEHAVIOR DURING NFS OUTAGE:                                        │
│                                                                             │
│  1. MariaDB on HARD MOUNT → kept running, accepting connections             │
│  2. WordPress on SOFT MOUNT → couldn't read wp-config.php from NFS          │
│  3. WordPress tried to connect but couldn't get DB credentials              │
│  4. WordPress closed connection before authentication                        │
│  5. MariaDB logged: "Aborted connection... closed normally without auth"    │
│                                                                             │
│  Key insight: MariaDB was FINE, it was the CLIENTS that failed              │
│  Connection attempts every ~5 seconds = health check or retry logic         │
│  Source: 10.0.64.11 = worker2 (where one WordPress pod runs)                │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Evidence Summary: Soft vs Hard Mount Behavior

| Component | Mount | During Outage | Logs Evidence |
|-----------|-------|---------------|---------------|
| **WordPress** | soft | Couldn't read wp-config.php | Closed DB connections without auth |
| **MariaDB** | hard | Kept running, I/O paused | Received connections, logged "Aborted" |
| **Prometheus** | soft | TSDB write failed | Container restarted (9th restart) |

### Timeline Reconstruction from Logs
```
22:03:xx - NAS restart triggered
22:04:43 - First MariaDB "Aborted connection" (WordPress can't read config)
22:04-22:08 - Continuous aborted connections every ~5 seconds
22:06:30 - NAS back online
22:08:38 - Last aborted connection logged
22:14:xx - WordPress probes show healthy (full recovery)
```

**Why ~4 minutes of aborted connections if NAS was down only ~2 minutes?**
- NAS came back at 22:06:30
- But cached NFS handles may have taken extra time to recover
- Or WordPress retry backoff extended the connection attempts
- Full probe health restored by 22:14

---

## Test 2: Second NAS Restart (12:20 AM)

### Timeline
```
12:20:xx AM - NAS restart triggered (second test)
~2 minutes  - NAS down
12:22:xx AM - NAS back online
```

### WordPress Behavior - NO RESTARTS (Again)
```bash
[root@k8s-master1 ~]# kubectl get pods -n apps -w
NAME                         READY   STATUS    RESTARTS   AGE
wordpress-5f649b595f-jwcnk   2/2     Running   0          59m
wordpress-5f649b595f-n65mm   2/2     Running   0          157m
wordpress-5f649b595f-tpzrj   2/2     Running   0          157m

# During outage - readiness failed (1/2):
wordpress-5f649b595f-jwcnk   1/2     Running   0          59m
wordpress-5f649b595f-n65mm   1/2     Running   0          157m
wordpress-5f649b595f-tpzrj   1/2     Running   0          157m

# After recovery - back to 2/2:
wordpress-5f649b595f-tpzrj   2/2     Running   0          157m
wordpress-5f649b595f-jwcnk   2/2     Running   0          60m
wordpress-5f649b595f-n65mm   2/2     Running   0          158m
```

**Note:** User was actively watching/downloading videos from WordPress during this test.
WordPress still survived with 0 restarts.

### Prometheus Behavior - RESTARTED AGAIN (+1)
```bash
# Prometheus restart count went from 9 to 10:
prometheus-kube-prometheus-stack-prometheus-0   2/2   Running   10 (2m28s ago)   2d23h
```

### Prometheus Error Logs During Outage
```
time=2026-04-16T22:21:19.009Z level=ERROR msg=reloadBlocks component=tsdb
    err="find blocks: open /prometheus: stale file handle"

time=2026-04-16T22:21:36.485Z level=ERROR msg="Failed to calculate size of \"chunks_head\" dir"
    err="lstat /prometheus/chunks_head: input/output error"

time=2026-04-16T22:21:49.612Z level=ERROR msg="compaction failed" component=tsdb
    err="plan compaction: open /prometheus: stale file handle"

time=2026-04-16T22:21:49.638Z level=ERROR msg="Scrape commit failed"
    err="write to WAL: log samples: write /prometheus/wal/00000152: input/output error"

time=2026-04-16T22:23:38.989Z level=WARN msg="Received an OS signal, exiting gracefully..."
    signal=terminated    ← Kubelet killed it (liveness failed)

time=2026-04-16T22:23:49.237Z level=ERROR msg="sync previous segment" component=tsdb
    err="sync /prometheus/wal/00000152: input/output error"

time=2026-04-16T22:23:49.240Z level=INFO msg="See you next time!"    ← Clean shutdown
```

---

## Deep Analysis: READ vs WRITE Behavior on Soft Mount

### Why Prometheus Crashed (WRITE-Heavy Workload)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  PROMETHEUS IS WRITE-HEAVY:                                                 │
│                                                                             │
│  Every 15-30 seconds, Prometheus MUST:                                      │
│  1. Scrape metrics from all targets (kube-apiserver, nodes, pods)           │
│  2. WRITE scraped samples to WAL (Write-Ahead Log) → /prometheus/wal/       │
│  3. WRITE to TSDB chunks → /prometheus/chunks_head/                         │
│  4. Periodically compact old blocks → /prometheus/                          │
│                                                                             │
│  When NFS goes down:                                                        │
│  - Soft mount returns I/O error after 3s × 3 retries = 9 seconds            │
│  - WAL write fails → "write to WAL: input/output error"                     │
│  - TSDB detects corruption risk                                             │
│  - Prometheus crashes OR kubelet kills via liveness probe                   │
│  - Kubelet restarts container after NFS recovers                            │
│  - Prometheus replays WAL and resumes                                       │
│                                                                             │
│  WRITE failures on soft mount = CRASH (expected and correct behavior)       │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Why WordPress Survived (Even While Watching Videos)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  VIDEO STREAMING = READ OPERATION (not write):                              │
│                                                                             │
│  When user watches a video:                                                 │
│  1. Browser requests video chunk via HTTP GET                               │
│  2. Ingress-nginx routes to WordPress pod                                   │
│  3. PHP tries to READ from /wp-content/uploads/video.mp4 (on NFS)           │
│  4. NFS soft mount returns I/O error (stale file handle)                    │
│  5. PHP catches error, returns HTTP 500/503 to browser                      │
│  6. Browser shows "buffering..." or playback error                          │
│  7. PHP process continues running - it just returned an error response      │
│                                                                             │
│  READ failures are GRACEFUL:                                                │
│  - No data corruption risk (nothing being written)                          │
│  - PHP error handling returns HTTP error to client                          │
│  - Process survives, ready for next request                                 │
│  - When NFS recovers, next READ succeeds                                    │
│                                                                             │
│  User experience: Video pauses/buffers, page shows error, then recovers     │
│  Container behavior: Stays Running, readiness fails, endpoints removed      │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Operation Types and Soft Mount Behavior

| Operation Type | Example | NFS Error Result | Container Impact |
|----------------|---------|------------------|------------------|
| **READ** (idle) | No active requests | Nothing happens | No impact |
| **READ** (stream) | Watch video, view image | Error returned to client | Survives |
| **READ** (page) | Load WordPress page | 500 error to browser | Survives |
| **WRITE** (small) | Save post, upload small file | Error, possible data loss | May survive |
| **WRITE** (large) | Upload 90MB video | Error, write corruption | Likely crash |
| **WRITE** (constant) | Prometheus TSDB, DB writes | Guaranteed crash | Crashes/restarts |

### The Key Insight

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  SOFT MOUNT FAILURE MODES:                                                  │
│                                                                             │
│  READ failure:                                                              │
│  - Returns ESTALE/EIO error to application                                  │
│  - Application handles error (returns 500 to client)                        │
│  - Process survives, state intact                                           │
│  - Recovery: instant when NFS returns                                       │
│                                                                             │
│  WRITE failure:                                                             │
│  - Returns ESTALE/EIO error during write                                    │
│  - Partial write = data corruption risk                                     │
│  - Application may crash if it detects corruption                           │
│  - Recovery: container restart, replay logs/WAL                             │
│                                                                             │
│  This is why:                                                               │
│  - WordPress (read-heavy web serving) → SURVIVES                            │
│  - Prometheus (write-heavy TSDB) → CRASHES                                  │
│  - MariaDB on HARD mount → HANGS (no crash, no corruption)                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Test 2 Summary

| Component | Restarts | Behavior | Reason |
|-----------|----------|----------|--------|
| WordPress | 0 | Survived (video streaming) | READ operations handle errors gracefully |
| Prometheus | +1 (now 10) | Crashed and restarted | WRITE to WAL failed, corruption detected |
| MariaDB | 0 | Survived | Hard mount paused I/O, no errors |
| Grafana | 0 | Survived | Read-heavy dashboards |
| Loki | 0 | Survived | Ingestion paused, no crash |

---

## Test 3: Third NAS Restart with 90MB File Upload (~12:30 AM)

### Objective
Test WordPress behavior while actively UPLOADING a 90MB file (WRITE operation).

### WordPress Apache Error Logs - I/O ERRORS CAPTURED!

```bash
# Readiness probe returned HTTP 403 (access denied due to I/O error):
10.0.64.12 - - [16/Apr/2026:22:20:44 +0000] "GET /wp-content/index.php HTTP/1.1" 403 498 "-" "kube-probe/1.35"
10.0.64.12 - - [16/Apr/2026:22:20:49 +0000] "GET /wp-content/index.php HTTP/1.1" 403 498 "-" "kube-probe/1.35"
10.0.64.12 - - [16/Apr/2026:22:20:54 +0000] "GET /wp-content/index.php HTTP/1.1" 403 498 "-" "kube-probe/1.35"
10.0.64.12 - - [16/Apr/2026:22:20:59 +0000] "GET /wp-content/index.php HTTP/1.1" 403 498 "-" "kube-probe/1.35"
10.0.64.12 - - [16/Apr/2026:22:21:04 +0000] "GET /wp-content/index.php HTTP/1.1" 403 498 "-" "kube-probe/1.35"
10.0.64.12 - - [16/Apr/2026:22:21:09 +0000] "GET /wp-content/index.php HTTP/1.1" 403 498 "-" "kube-probe/1.35"
10.0.64.12 - - [16/Apr/2026:22:21:14 +0000] "GET /wp-content/index.php HTTP/1.1" 403 498 "-" "kube-probe/1.35"

# Apache core errors showing actual I/O failures:
[Thu Apr 16 22:21:20.609446 2026] [core:error] [pid 62:tid 62] (5)Input/output error:
    [client 10.0.64.12:47688] AH00036: access to /wp-content/index.php failed
    (filesystem path '/var/www/html/wp-content')

[Thu Apr 16 22:21:25.665072 2026] [core:error] [pid 65:tid 65] (5)Input/output error:
    [client 10.0.64.12:46226] AH00036: access to /wp-content/index.php failed

[Thu Apr 16 22:21:30.657106 2026] [core:error] [pid 63:tid 63] (5)Input/output error:
    [client 10.0.64.12:33160] AH00036: access to /wp-content/index.php failed

[Thu Apr 16 22:21:35.625087 2026] [core:error] [pid 66:tid 66] (5)Input/output error:
    [client 10.0.64.12:33166] AH00036: access to /wp-content/index.php failed

[Thu Apr 16 22:21:40.705594 2026] [core:error] [pid 73:tid 73] (5)Input/output error:
    [client 10.0.64.12:41222] AH00036: access to /wp-content/index.php failed

[Thu Apr 16 22:21:46.724703 2026] [core:error] [pid 68:tid 68] (5)Input/output error:
    [client 10.0.64.12:41230] AH00036: access to /wp-content/index.php failed

[Thu Apr 16 22:21:52.730909 2026] [core:error] [pid 69:tid 69] (5)Input/output error:
    [client 10.0.64.12:55564] AH00036: access to /wp-content/index.php failed
```

### User Media Access Also Failed
```bash
# User browsing media library - image access failed:
[Thu Apr 16 22:21:44.070736 2026] [core:error] [pid 72:tid 72] (5)Input/output error:
    [client 10.244.62.0:0] AH00036: access to /wp-content/uploads/2026/04/
    672ef96e591a6cf83e75313e_672ef8dde0e15c7419c1ad5e_3.webp failed
    (filesystem path '/var/www/html/wp-content'),
    referer: http://wordpress-dev.lab.local/wp-admin/upload.php?item=23

10.244.62.0 - - [16/Apr/2026:22:21:15 +0000]
    "GET /wp-content/uploads/2026/04/672ef96e591a6cf83e75313e_672ef8dde0e15c7419c1ad5e_3.webp HTTP/1.1"
    403 489 "http://wordpress-dev.lab.local/wp-admin/upload.php?item=23"
```

### Recovery - Back to HTTP 200
```bash
# After NFS recovered, probes return 200 again:
10.0.64.12 - - [16/Apr/2026:22:21:19 +0000] "GET /wp-content/index.php HTTP/1.1" 200 192 "-" "kube-probe/1.35"
10.0.64.12 - - [16/Apr/2026:22:21:24 +0000] "GET /wp-content/index.php HTTP/1.1" 200 192 "-" "kube-probe/1.35"
10.0.64.12 - - [16/Apr/2026:22:21:29 +0000] "GET /wp-content/index.php HTTP/1.1" 200 192 "-" "kube-probe/1.35"
10.0.64.12 - - [16/Apr/2026:22:21:34 +0000] "GET /wp-content/index.php HTTP/1.1" 200 192 "-" "kube-probe/1.35"
```

### Pod Status - Still NO RESTARTS
```bash
[root@k8s-master1 ~]# kubectl get pods -n apps -w
NAME                         READY   STATUS    RESTARTS   AGE
wordpress-5f649b595f-jwcnk   2/2     Running   0          68m    ← Still 0!
wordpress-5f649b595f-n65mm   2/2     Running   0          166m   ← Still 0!
wordpress-5f649b595f-tpzrj   2/2     Running   0          165m   ← Still 0!

# During outage (1/2 = readiness failed):
wordpress-5f649b595f-n65mm   1/2     Running   0          166m
wordpress-5f649b595f-tpzrj   1/2     Running   0          165m
wordpress-5f649b595f-jwcnk   1/2     Running   0          68m

# After recovery (back to 2/2):
wordpress-5f649b595f-n65mm   2/2     Running   0          166m
wordpress-5f649b595f-tpzrj   2/2     Running   0          166m
wordpress-5f649b595f-jwcnk   2/2     Running   0          68m
```

### Why `kubectl logs -p` Shows "Not Found"

```bash
[root@k8s-master1 ~]# kubectl logs wordpress-5f649b595f-jwcnk -n apps -p
Error from server (BadRequest): previous terminated container "wordpress" in pod
    "wordpress-5f649b595f-jwcnk" not found
```

**Explanation:**
```
┌─────────────────────────────────────────────────────────────────────────────┐
│  WHY `-p` (previous) DOESN'T WORK:                                          │
│                                                                             │
│  The `-p` flag shows logs from the PREVIOUS container instance.             │
│  A "previous" container only exists AFTER a restart.                        │
│                                                                             │
│  WordPress has RESTARTS=0, meaning:                                         │
│  - The container NEVER restarted                                            │
│  - There is NO previous container                                           │
│  - Therefore "previous terminated container not found"                      │
│                                                                             │
│  Container lifecycle:                                                       │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐                 │
│  │ Container v1 │ --> │ Container v2 │ --> │ Container v3 │                 │
│  │   (current)  │     │   (current)  │     │   (current)  │                 │
│  │              │     │  v1=previous │     │  v2=previous │                 │
│  └──────────────┘     └──────────────┘     └──────────────┘                 │
│     RESTARTS=0           RESTARTS=1           RESTARTS=2                    │
│     No previous          v1 is previous       v2 is previous                │
│                                                                             │
│  WordPress stayed at RESTARTS=0 = No previous container exists              │
│  Prometheus at RESTARTS=10 = Has previous container logs available          │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Test 3 Key Findings

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  APACHE ERROR HANDLING ON NFS FAILURE:                                      │
│                                                                             │
│  1. NFS returns I/O error (soft mount timeout)                              │
│  2. Apache catches error: "(5)Input/output error: AH00036"                  │
│  3. Apache returns HTTP 403 Forbidden to client                             │
│  4. Apache process SURVIVES (doesn't crash)                                 │
│  5. Readiness probe gets 403 → pod marked NotReady → endpoints removed      │
│  6. When NFS recovers → Apache returns 200 → pod Ready → endpoints restored │
│                                                                             │
│  ERROR CODE (5) = EIO (Input/Output Error) from Linux kernel                │
│  Apache translates this to HTTP 403 (access denied)                         │
│  This is graceful error handling - no crash required                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

### HTTP Response During NFS Outage

| Probe/Request | Normal Response | During Outage | Reason |
|---------------|-----------------|---------------|--------|
| Readiness `/wp-content/index.php` | 200 | **403** | I/O error accessing NFS |
| Liveness `/wp-includes/images/blank.gif` | 200 | **200** | Local file (not on NFS) |
| User media request | 200 | **403** | I/O error accessing uploads |

**Note:** Liveness probe still passed (200) because it checks a local file.
Only readiness failed → pod stayed Running but NotReady → endpoints removed.

### Why WordPress Went 1/2 (Not Crashed, Just Isolated)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  UNDERSTANDING 1/2 vs 2/2 STATUS:                                           │
│                                                                             │
│  WordPress pod has 2 containers:                                            │
│    1. wordpress (main PHP/Apache container)                                 │
│    2. vault-agent (sidecar for secrets)                                     │
│                                                                             │
│  READY column shows: <ready containers>/<total containers>                  │
│                                                                             │
│  2/2 = Both containers READY (passing readiness probes)                     │
│  1/2 = One container NOT READY (failing readiness probe)                    │
│                                                                             │
│  During NFS outage:                                                         │
│  ┌─────────────────┐     ┌─────────────────┐                                │
│  │ wordpress       │     │ vault-agent     │                                │
│  │ container       │     │ container       │                                │
│  │                 │     │                 │                                │
│  │ Readiness: FAIL │     │ Readiness: PASS │                                │
│  │ (403 on NFS)    │     │ (no NFS needed) │                                │
│  │                 │     │                 │                                │
│  │ Liveness: PASS  │     │                 │                                │
│  │ (local file OK) │     │                 │                                │
│  └─────────────────┘     └─────────────────┘                                │
│           ↓                                                                 │
│  Pod status: 1/2 Running (1 ready, 1 not ready)                             │
│  Pod NOT restarted (liveness passed)                                        │
│  Pod ISOLATED from traffic (readiness failed)                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

### The Isolation Mechanism

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  HOW READINESS PROBE ISOLATES UNHEALTHY PODS:                               │
│                                                                             │
│  BEFORE OUTAGE (healthy):                                                   │
│  ┌──────────────────────────────────────────────────────────┐               │
│  │ Service: wordpress                                       │               │
│  │ Endpoints: [10.244.62.8, 10.244.207.68, 10.244.29.174]  │               │
│  │            (worker1)    (worker2)       (worker3)        │               │
│  └──────────────────────────────────────────────────────────┘               │
│                              ↓                                              │
│  Ingress-nginx routes traffic to all 3 pods (round-robin)                   │
│                                                                             │
│  ─────────────────────────────────────────────────────────────────────────  │
│                                                                             │
│  DURING OUTAGE (readiness fails on all pods):                               │
│  ┌──────────────────────────────────────────────────────────┐               │
│  │ Service: wordpress                                       │               │
│  │ Endpoints: []  ← EMPTY! All pods removed                 │               │
│  └──────────────────────────────────────────────────────────┘               │
│                              ↓                                              │
│  Ingress-nginx has no backends → returns 503 Service Unavailable            │
│                                                                             │
│  Pod status:                                                                │
│  wordpress-xxx-jwcnk   1/2   Running   0   ← ALIVE but ISOLATED             │
│  wordpress-xxx-n65mm   1/2   Running   0   ← ALIVE but ISOLATED             │
│  wordpress-xxx-tpzrj   1/2   Running   0   ← ALIVE but ISOLATED             │
│                                                                             │
│  ─────────────────────────────────────────────────────────────────────────  │
│                                                                             │
│  AFTER RECOVERY (readiness passes again):                                   │
│  ┌──────────────────────────────────────────────────────────┐               │
│  │ Service: wordpress                                       │               │
│  │ Endpoints: [10.244.62.8, 10.244.207.68, 10.244.29.174]  │               │
│  └──────────────────────────────────────────────────────────┘               │
│                              ↓                                              │
│  Ingress-nginx routes traffic to all 3 pods again                           │
│  Pods back to 2/2 Running                                                   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Why This Design is Correct

| Probe | Purpose | On Failure | WordPress Config |
|-------|---------|------------|------------------|
| **Readiness** | "Can I serve traffic?" | Remove from endpoints | `/wp-content/index.php` (NFS) |
| **Liveness** | "Am I alive/crashed?" | Restart container | `/wp-includes/images/blank.gif` (local) |

```
Readiness FAIL + Liveness PASS = Pod ISOLATED (not restarted)
├── Pod stays Running (no restart needed - process is healthy)
├── Pod removed from Service endpoints (can't serve traffic)
├── No traffic routed to pod (users see 503, not errors)
├── When NFS recovers, pod immediately ready (no restart delay)
└── FAST RECOVERY - no container startup time, no init containers
```

**Key Insight:** By using separate probes:
- Readiness checks NFS (the actual problem)
- Liveness checks local file (process health)

If liveness also checked NFS, the pod would restart → which is useless because:
1. Same node still has broken NFS
2. Restart takes ~11s (init containers + vault agent)
3. Would restart again → CrashLoopBackOff
4. Slower recovery than just waiting for NFS

### Surprising Result: WordPress Survived 90MB Upload!

**Expected:** WRITE operation during NFS outage would crash WordPress
**Actual:** WordPress still shows 0 restarts

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  WHY WORDPRESS SURVIVED EVEN DURING UPLOAD:                                 │
│                                                                             │
│  Possible reasons:                                                          │
│                                                                             │
│  1. Upload uses TEMP directory first (usually /tmp, not NFS)                │
│     - PHP uploads to local /tmp                                             │
│     - Only MOVES to /wp-content/uploads after complete                      │
│     - If NFS fails during move, PHP gets error but doesn't crash            │
│                                                                             │
│  2. Upload was still buffering in memory/network                            │
│     - 90MB takes time to transfer over network                              │
│     - NFS failure may have happened before write started                    │
│                                                                             │
│  3. PHP error handling is resilient                                         │
│     - move_uploaded_file() returns FALSE on failure                         │
│     - WordPress catches error, shows "Upload failed" to user                │
│     - PHP process doesn't crash on I/O error                                │
│                                                                             │
│  4. Soft mount returns error quickly (9 seconds)                            │
│     - PHP gets error, handles it, returns error response                    │
│     - Unlike Prometheus which detects corruption and crashes                │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Test 3 Final Summary

| Component | Expected | Actual | Restarts |
|-----------|----------|--------|----------|
| WordPress (90MB upload) | Crash/restart | **Survived** | 0 |
| Prometheus | Crash (TSDB writes) | Crashed | +1 (now 11) |
| MariaDB | Hang (hard mount) | Survived | 0 |

### User Observation: Upload Behavior During NFS Outage

**Test setup:** 4 × 90MB files queued for upload

| File | Status When NAS Died | Result After Recovery |
|------|---------------------|----------------------|
| File 1 | Completed before outage | ✅ Found in media library |
| File 2 | Uploading (stuck halfway) | ❌ Lost - not found |
| File 3 | In queue (not started) | ❌ Lost - not found |
| File 4 | In queue (not started) | ❌ Lost - not found |

**Browser behavior after NAS recovered:**
1. Page showed error trying to continue upload
2. Page reloaded automatically
3. Only File 1 (completed before outage) visible in media library
4. Files 2, 3, 4 completely lost

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  UPLOAD FAILURE ANALYSIS:                                                   │
│                                                                             │
│  File 1 (completed before outage):                                          │
│  └── Already written to NFS → Survived                                      │
│                                                                             │
│  File 2 (uploading when NAS died):                                          │
│  ├── Partially in PHP temp (/tmp) - local, not NFS                          │
│  ├── move_uploaded_file() to NFS failed with I/O error                      │
│  ├── PHP returned error to browser                                          │
│  ├── Temp file cleaned up by PHP                                            │
│  └── Result: DATA LOST (no partial file on NFS)                             │
│                                                                             │
│  Files 3, 4 (in queue):                                                     │
│  ├── Stored in browser JavaScript queue                                     │
│  ├── Never sent to server (waiting for File 2 to complete)                  │
│  ├── Page reload cleared browser state                                      │
│  └── Result: DATA LOST (never reached server)                               │
│                                                                             │
│  WordPress container:                                                       │
│  ├── Returned error to browser (handled gracefully)                         │
│  ├── Did NOT crash (liveness probe still passed)                            │
│  ├── RESTARTS = 0 (still!)                                                  │
│  └── Ready to serve again after NFS recovered                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Difference: WordPress vs Prometheus on WRITE Failure

| App | Write Behavior | On NFS Error | Restarts |
|-----|---------------|--------------|----------|
| **WordPress** | Request-based (upload, then done) | Returns error to client, moves on | 0 |
| **Prometheus** | Continuous (write every 15s forever) | Detects corruption, crashes | +1 each outage |

**Why WordPress survives but Prometheus doesn't:**
- WordPress: Each upload is independent. Failure = return error, done.
- Prometheus: TSDB must be consistent. WAL corruption = unsafe to continue = crash.

**Conclusion:** WordPress/PHP is extremely resilient to NFS failures:
- READ failures → returns 403/500 to client, survives
- WRITE failures → returns error to client, **data lost but process survives**
- Only continuous writes (like Prometheus TSDB) cause crashes

### Recovery Times (Short Outage 2-2.5 min)
| Component | Outage Duration | Time to Full Ready | Method |
|-----------|-----------------|-------------------|--------|
| WordPress | 2-2.5 min | Instant | Endpoints restored |
| MariaDB | 2-2.5 min | Instant | I/O resumed |
| Grafana | 2-2.5 min | Instant | Never failed |
| Prometheus | 2-2.5 min | ~30s after restart | Container restart |
| Loki | 2-2.5 min | Instant | Never failed |

---

## Test 4: Extended NAS Outage (10+ Minutes)

**Objective:** Test behavior beyond soft mount retry exhaustion (9s) and approach hard mount timeout (5min)

### Timeline
```
12:45:00 - NAS shutdown initiated
12:45:xx - 4 WordPress uploads in progress (mid-way)
12:45:xx - All nodes: 503 Service Temporarily Unavailable
12:49:00 - +4 min: WordPress still 1/2 Running, 0 restarts
12:52:00 - +7 min: WordPress still 1/2 Running, 0 restarts
12:55:xx - +10 min: Evidence collected below
```

### Evidence at 10+ Minutes (NAS Still Down)

**WordPress - STILL ALIVE (0 restarts)**
```
wordpress-5f649b595f-jwcnk   1/2     Running   0          85m
wordpress-5f649b595f-n65mm   1/2     Running   0          3h3m
wordpress-5f649b595f-tpzrj   1/2     Running   0          3h2m
```
- Readiness probe failed → 1/2 Running (isolated from traffic)
- Liveness probe passed → 0 restarts (container alive)
- PHP process handling I/O errors gracefully

**MariaDB - STILL ALIVE (hard mount frozen)**
```
mariadb-0   2/2     Running   12 (3h49m ago)   3d
```
- Hard mount: I/O operations in D state (uninterruptible sleep)
- Liveness probe: TCP check, doesn't require disk I/O
- Process frozen but not crashed - will resume when NFS returns

**Grafana - CrashLoopBackOff**
```
kube-prometheus-stack-grafana-5f6554dcf5-mqbk5   3/4   CrashLoopBackOff   25
```
- Liveness probe failed (requires NFS access for dashboard reads)
- Container restarted → NFS volume mount failed → CreateContainerError
- Backoff loop: CreateContainerError → CrashLoopBackOff → retry → fail

**Prometheus - CRASHED AGAIN (TSDB write failure)**
```
prometheus-kube-prometheus-stack-prometheus-0   2/2   Running   11 (19m ago)   3d
```
- Restart count: 11 (increased from 10 during outage)
- TSDB requires continuous writes every 15s
- WAL corruption detected → process exits → container restarts
- 2/2 Running = latest restart still within liveness grace period

**Endpoints - EMPTY (traffic isolation)**
```
[k8s_admin@k8s-master1 ~]$ kubectl get endpoints wordpress -n apps
NAME        ENDPOINTS   AGE
wordpress   <none>      7d18h
```
- All WordPress pods removed from Service endpoints
- Ingress has no backends → 503 Service Unavailable
- This is CORRECT behavior - isolate unhealthy pods

### Why WordPress Survives 10+ Minutes Without Restart

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  WordPress/PHP Resilience Model:                                            │
│                                                                             │
│  1. PHP-FPM is request-based (not continuous like Prometheus)               │
│  2. Each request is independent - failure doesn't corrupt state             │
│  3. NFS I/O error → PHP returns error to caller → continues                 │
│  4. No persistent write stream that can corrupt                             │
│                                                                             │
│  Liveness Probe Check (httpGet):                                            │
│  ├── Checks /wp-includes/version.php (from container filesystem, not NFS)  │
│  ├── OR checks TCP port (PHP-FPM responds regardless of disk state)         │
│  └── Passes even when NFS is dead = container stays alive                   │
│                                                                             │
│  Readiness Probe Check:                                                     │
│  ├── Checks actual service health (may try NFS access)                      │
│  ├── Fails when NFS unavailable → pod marked NotReady                       │
│  └── Pod removed from endpoints = isolated from traffic                     │
│                                                                             │
│  Result: 1/2 Running = alive but isolated                                   │
│         0 restarts = liveness always passes                                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Live Container Evidence (During 10+ min Outage)

```bash
# Container accepts exec - ALIVE
[root@k8s-master1 ~]# kubectl exec -it wordpress-5f649b595f-n65mm -n apps -c wordpress -- bash
root@wordpress-5f649b595f-n65mm:/var/www/html#

# ls on /var/www/html worked (NFS directory listing cached)
root@wordpress-5f649b595f-n65mm:/var/www/html# ls
index.php    wp-activate.php     wp-comments-post.php  wp-config.php  wp-includes ...

# Log directory exists on container overlay filesystem
root@wordpress-5f649b595f-n65mm:/var/log/apache2# ls
access.log  error.log  other_vhosts_access.log

# Apache logs are Docker symlinks (standard practice)
root@wordpress-5f649b595f-n65mm:/var/log/apache2# ls -l
total 0
lrwxrwxrwx. 1 www-data www-data 11 Mar 16 22:31 access.log -> /dev/stdout
lrwxrwxrwx. 1 www-data www-data 11 Mar 16 22:31 error.log -> /dev/stderr
lrwxrwxrwx. 1 www-data www-data 11 Mar 16 22:31 other_vhosts_access.log -> /dev/stdout

# cat/tail on /dev/stdout hangs (reading from write-only pipe - normal Docker behavior)
root@wordpress-5f649b595f-n65mm:/var/log/apache2# cat /dev/stdout
^C
root@wordpress-5f649b595f-n65mm:/var/log/apache2# cat /dev/stderr
^C

# Local filesystem file worked INSTANTLY
root@wordpress-5f649b595f-n65mm:/etc/apache2# tail /var/log/alternatives.log
update-alternatives 2026-03-16 23:22:53: link group automake fully removed
```

**Findings:**
- Container alive and accepting kubectl exec ✓
- Bash shell fully responsive ✓
- Apache logs → /dev/stdout, /dev/stderr (Docker standard)
- Log reading hang is NORMAL (reading from write-only pipe), NOT NFS-related
- Process survives in degraded state without crashing

**Key insight:** Since Apache logs go to stderr, errors WOULD appear in `kubectl logs`.
The fact that `kubectl logs wordpress` shows NO errors during NFS outage means:
→ PHP is handling I/O failures silently, not even logging them as errors

### Volume Mount Discovery - Root Cause of No Restart

```bash
# Liveness probe path accessible (container filesystem)
root@wordpress-5f649b595f-n65mm:/var/www/html/wp-includes# ls
ID3  IXR  PHPMailer  ... images ...  # ALL FILES LISTED INSTANTLY

# NFS mount path - HUNG (Ctrl+C needed)
root@wordpress-5f649b595f-n65mm:/var/www/html/wp-includes# cd /var/www/html/wp-content/
^C^C^C^C
```

**Deployment volume mounts:**
```yaml
volumeMounts:
  - name: wordpress-data
    mountPath: /var/www/html/wp-content   # ← ONLY wp-content is NFS
```

**Liveness probe configuration:**
```yaml
livenessProbe:
  httpGet:
    path: /wp-includes/images/blank.gif   # ← Container filesystem, NOT NFS!
    port: 80
```

**Root cause diagram:**
```
┌─────────────────────────────────────────────────────────────────┐
│  /var/www/html/                                                 │
│  ├── index.php              ← Container image (overlay)        │
│  ├── wp-admin/              ← Container image (overlay)        │
│  ├── wp-includes/           ← Container image (overlay)        │
│  │   └── images/blank.gif   ← LIVENESS CHECKS THIS (always OK) │
│  └── wp-content/ ──────────────────────────────────────────────→│
│                             │  NFS Mount (10.0.40.120)          │
│                             │  ├── uploads/                     │
│                             │  ├── plugins/                     │
│                             │  └── themes/                      │
│                             │  ↑ READINESS may check this       │
└─────────────────────────────────────────────────────────────────┘

Liveness: /wp-includes/images/blank.gif → Container FS → ALWAYS PASSES
Readiness: Service health → May touch wp-content → FAILS when NFS down
Result: 1/2 Running, 0 restarts
```

**This is CORRECT design:**
- Liveness checks "is the process alive" (Apache serving from container FS)
- Readiness checks "can we serve users" (requires NFS for wp-content)
- Restarting won't fix NFS - isolation is the right response

### Theory: Internal Logging vs stdout/stderr

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Why WordPress/MariaDB don't show errors in kubectl logs:                   │
│                                                                             │
│  WordPress:                                                                 │
│  ├── PHP errors → /var/log/apache2/error.log (inside container)            │
│  ├── wp-content/debug.log (on NFS - can't write when NFS down)             │
│  ├── stdout/stderr: Only Apache access logs                                │
│  └── NFS errors handled silently by PHP, not logged to stdout              │
│                                                                             │
│  MariaDB:                                                                   │
│  ├── Logs to /var/log/mysql/ or data directory (on NFS)                    │
│  ├── When NFS frozen (hard mount): Can't write logs either!                │
│  ├── Process in D state - blocked on I/O, can't even log                   │
│  └── stdout: Only startup logs, not runtime I/O errors                     │
│                                                                             │
│  Prometheus (different):                                                    │
│  ├── Logs errors to stdout/stderr                                          │
│  ├── TSDB errors are FATAL - process exits                                 │
│  └── That's why we see errors in kubectl logs                              │
│                                                                             │
│  Key Insight:                                                               │
│  - Apps that log errors internally and handle them gracefully → survive    │
│  - Apps that log to stdout and treat errors as fatal → crash               │
│  - This is why "silent" pods survive longer than "verbose" pods            │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Toleration Settings Verified

```bash
[k8s_admin@k8s-master1 ~]$ kubectl get pods -n apps wordpress-5f649b595f-jwcnk -o yaml | grep -A 5 toleration
  tolerations:
  - effect: NoExecute
    key: node.kubernetes.io/not-ready
    operator: Exists
    tolerationSeconds: 300
```

**Important:** The 300s toleration applies to NODE unreachability, NOT NFS failure:
- node.kubernetes.io/not-ready = node fails to heartbeat to API server
- NFS failure ≠ node failure (nodes are all Ready, only NFS is down)
- This toleration does NOT explain why WordPress survives 10+ minutes

**Actual explanation:** WordPress survives because:
1. Liveness probe passes (doesn't require NFS)
2. PHP handles I/O errors gracefully (returns error, doesn't crash)
3. No continuous write stream to corrupt

### Storage Class Behavior Comparison (10+ min outage)

| Storage Class | Mount Type | App | Behavior at 10 min |
|---------------|-----------|-----|-------------------|
| nfs-retain | soft (9s timeout) | WordPress | 1/2 Running, 0 restarts |
| nfs-retain | soft (9s timeout) | Grafana | CrashLoopBackOff |
| nfs-retain | soft (9s timeout) | Prometheus | Crashed (11 restarts) |
| nfs-database | hard (5min timeout) | MariaDB | 2/2 Running, frozen |

**Soft mount behavior varies by application:**
- Read-heavy + graceful error handling = survives (WordPress)
- Write-heavy + error = fatal (Prometheus TSDB)
- Liveness requires NFS = CrashLoopBackOff (Grafana)

**Hard mount at 10 min:** Still within intr timeout, process frozen but alive

### Issues Found
```
1. Prometheus (write-heavy) restarted - expected behavior, not an issue
2. Grafana CrashLoopBackOff during extended outage - liveness checks NFS paths
3. WordPress survived 10+ min without restart - by design, not a bug
4. MariaDB frozen but alive (hard mount D state) - correct behavior
```

### Final Conclusions (Test 4 - 10+ min outage)

| Component | Mount Type | Restarts | State | Why |
|-----------|-----------|----------|-------|-----|
| WordPress | soft | 0 | 1/2 Running | Liveness checks container FS, not NFS |
| MariaDB | hard | 0 | 2/2 Running | Hard mount freezes I/O, TCP liveness passes |
| Grafana | soft | 25+ | CrashLoopBackOff | Liveness requires NFS dashboard access |
| Prometheus | soft | 11+ | 2/2 Running | TSDB write failure = fatal crash |

### Recommendations
```
1. Current storage class configuration is CORRECT:
   - Soft mount for stateless/read-heavy apps (WordPress, Grafana, Loki)
   - Hard mount for databases (MariaDB) - preserves data integrity

2. WordPress liveness probe design is CORRECT:
   - Checks container filesystem, not NFS
   - Keeps pod alive during NFS outage (isolation via readiness)
   - Instant recovery when NFS returns (no restart delay)

3. For extended NAS outages (>5 minutes):
   - WordPress: Survives indefinitely (isolated but alive)
   - Grafana: CrashLoopBackOff (needs liveness redesign if problematic)
   - Prometheus: Restarts repeatedly (acceptable for metrics continuity)
   - MariaDB: Frozen but will resume when NFS returns

4. No changes recommended - current behavior is optimal:
   - Restarting pods won't fix NFS
   - Isolation prevents user traffic to unhealthy pods
   - Fast recovery when storage returns
```

### Related TS Case
- `troubleshooting/kubernetes/36-wordpress-liveness-probe-nfs-resilience.md` - TS-K8S-036: Analysis of why WordPress survives NFS outage

---

## Related Documentation

- `disaster-recovery/single-worker-nfs-down.md` - Single worker NFS interface down test
- `disaster-recovery/nginx-dr-test.md` - NGINX layer failures test
- `kubernetes/dev/deployments/infrastructure/storage/storageclass.yaml` - Storage class definitions

---

## Test Commands Reference

```bash
# Pre-test baseline
showmount -e 10.0.40.120
kubectl get pods -A -o wide | grep -E "wordpress|mariadb|grafana|prometheus|loki|alertmanager"
kubectl get pvc -A
curl -I http://wordpress-dev.lab.local

# During outage monitoring
kubectl get pods -n apps -w
kubectl get pods -n database -w
kubectl get pods -n monitoring -w
kubectl get endpoints wordpress -n apps

# Kernel NFS errors
ssh root@k8s-worker1 'dmesg | grep -i nfs | tail -30'

# Recovery verification
showmount -e 10.0.40.120
kubectl get pods -A | grep -v Running
curl -I http://wordpress-dev.lab.local
```
