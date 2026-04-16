# TS-K8S-036 | 2026-04-17 | DOCUMENTED (By Design)
_____________________________________________________________________

[Info]
Domain: Kubernetes / Storage / Probes
Sub-techs: NFS, Liveness Probe, Readiness Probe, Volume Mounts, Pod Lifecycle
Environment: DEV lab.local | k8s-worker1/2/3, NAS (10.0.40.120)
Re-opened: No

_____________________________________________________________________

[Issue Description]
During Full NAS Shutdown DR test (10+ minutes outage), WordPress pods showed
unexpected behavior: 0 restarts despite NFS being completely down.

Initial observation:
```
wordpress-5f649b595f-jwcnk   1/2     Running   0          85m
wordpress-5f649b595f-n65mm   1/2     Running   0          3h3m
wordpress-5f649b595f-tpzrj   1/2     Running   0          3h2m
```

Expected: Liveness probe failure → container restart
Actual: 1/2 Running (readiness failed, liveness passed) → 0 restarts

_____________________________________________________________________

[Analysis]

# Volume Mount Configuration

```yaml
# deployment.yaml
volumeMounts:
  - name: wordpress-data
    mountPath: /var/www/html/wp-content   # ONLY wp-content on NFS
  - name: php-config
    mountPath: /usr/local/etc/php/conf.d/uploads.ini
```

WordPress core files (`/var/www/html/wp-includes/`, `/var/www/html/wp-admin/`)
are baked into the Docker image (container overlay filesystem).

Only `/var/www/html/wp-content/` (uploads, plugins, themes) is mounted from NFS.


# Liveness Probe Configuration

```yaml
livenessProbe:
  httpGet:
    path: /wp-includes/images/blank.gif   # Container filesystem!
    port: 80
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

The liveness probe checks `/wp-includes/images/blank.gif` which is:
- Part of WordPress core
- Stored on container overlay filesystem (Docker image)
- NOT on NFS mount

Therefore: **Liveness probe NEVER touches NFS → Always passes**


# Live Evidence (During NAS Outage)

```bash
# Container accessible via exec
[root@k8s-master1 ~]# kubectl exec -it wordpress-5f649b595f-n65mm -n apps -c wordpress -- bash

# wp-includes accessible instantly (container filesystem)
root@wordpress-5f649b595f-n65mm:/var/www/html/wp-includes# ls
ID3  IXR  PHPMailer  Requests  SimplePie  Text  abilities-api  ...  images  ...

# wp-content HUNG (NFS mount)
root@wordpress-5f649b595f-n65mm:/var/www/html/wp-includes# cd /var/www/html/wp-content/
^C^C^C^C  # Required Ctrl+C to escape
```

_____________________________________________________________________

[Root Cause]

```
┌─────────────────────────────────────────────────────────────────┐
│  /var/www/html/                                                 │
│  ├── index.php              ← Container image (overlay)        │
│  ├── wp-admin/              ← Container image (overlay)        │
│  ├── wp-includes/           ← Container image (overlay)        │
│  │   └── images/blank.gif   ← LIVENESS CHECKS THIS             │
│  │                             Always accessible = always pass  │
│  └── wp-content/ ──────────────────────────────────────────────→│
│                             │  NFS Mount (10.0.40.120)          │
│                             │  ├── uploads/                     │
│                             │  ├── plugins/                     │
│                             │  └── themes/                      │
│                             │  ↑ READINESS checks service       │
│                             │    Fails when NFS down            │
└─────────────────────────────────────────────────────────────────┘
```

Liveness: `/wp-includes/images/blank.gif` → Container FS → **ALWAYS PASSES**
Readiness: Service health check → May access wp-content → **FAILS when NFS down**
Result: `1/2 Running`, `0 restarts`

_____________________________________________________________________

[Behavior Comparison]

| Component | Mount Type | Liveness Check | Restarts (10 min outage) | Why |
|-----------|-----------|----------------|--------------------------|-----|
| WordPress | soft | Container FS path | 0 | Liveness never touches NFS |
| MariaDB | hard | TCP port check | 0 | TCP works, I/O frozen |
| Grafana | soft | Dashboard access (NFS) | 25+ | Liveness requires NFS |
| Prometheus | soft | Web UI + TSDB | 11+ | Write failure = fatal crash |

_____________________________________________________________________

[Resolution]

**Status: DOCUMENTED (By Design)**

This is CORRECT and OPTIMAL behavior:

1. **Restarting won't fix NFS**
   - Container restart cannot resolve NAS outage
   - Would cause unnecessary CrashLoopBackOff (like Grafana)

2. **Isolation via readiness is the right response**
   - 1/2 Running = process alive but isolated from traffic
   - Endpoints removed → ingress returns 503 → users see "maintenance"
   - No traffic sent to pod that can't serve properly

3. **Instant recovery when NFS returns**
   - No restart delay (30s init + startup time)
   - Readiness passes immediately → endpoints restored
   - Traffic resumes within probe interval (10s)

4. **PHP handles I/O errors gracefully**
   - Returns HTTP error to client, doesn't crash
   - Each request independent (no persistent state like Prometheus TSDB)

_____________________________________________________________________

[Anti-Pattern Warning]

If liveness probe checked an NFS path (like `/wp-content/health.txt`):

```yaml
# BAD - Would cause CrashLoopBackOff during NFS outage
livenessProbe:
  httpGet:
    path: /wp-content/health.txt   # ON NFS!
    port: 80
```

Behavior:
1. NFS down → HTTP timeout/error → liveness fails
2. Container restarts → NFS volume mount fails
3. CreateContainerError → CrashLoopBackOff
4. Pod stuck in loop until NFS recovers

This is exactly what happens to Grafana (liveness checks dashboards on NFS).

_____________________________________________________________________

[Design Recommendations]

For NFS-backed applications:

1. **Liveness probe should check container filesystem paths**
   - Static files baked into image
   - Health endpoint that doesn't require storage
   - TCP port check (if applicable)

2. **Readiness probe should check service capability**
   - May include storage-dependent checks
   - Failure = isolation, not restart

3. **Separate concerns:**
   - Liveness = "Is the process alive?"
   - Readiness = "Can we serve traffic?"

_____________________________________________________________________

[Related Cases]
- disaster-recovery/full-nas-shutdown.md - Full DR test documentation
- TS-K8S-029 - WordPress readiness probe NFS detection
- TS-K8S-015 - CSI-NFS restart stale mount MariaDB crash
- TS-K8S-003 - NFS hard mount pod unresponsiveness

_____________________________________________________________________

[References]
- kubernetes/dev/deployments/apps/wordpress/deployment.yaml (lines 100-107, 119-123)
- kubernetes/dev/deployments/infrastructure/storage/storageclass.yaml

_____________________________________________________________________

[Evidence Summary]

Test Conditions:
- NAS (10.0.40.120) shutdown for 10+ minutes
- All NFS mounts on all worker nodes affected
- Ingress returning 503 Service Unavailable

WordPress Behavior:
```
# At 10+ minutes into outage
wordpress-5f649b595f-jwcnk   1/2     Running   0          85m
wordpress-5f649b595f-n65mm   1/2     Running   0          3h3m
wordpress-5f649b595f-tpzrj   1/2     Running   0          3h2m

# Endpoints empty (traffic isolated)
kubectl get endpoints wordpress -n apps
NAME        ENDPOINTS   AGE
wordpress   <none>      7d18h
```

Container State Verification:
```bash
# kubectl exec works - container ALIVE
kubectl exec -it wordpress-5f649b595f-n65mm -n apps -c wordpress -- bash

# ls /var/www/html/wp-includes/ - WORKS (container FS)
# cd /var/www/html/wp-content/  - HANGS (NFS mount)
```

Conclusion: Liveness probe design correctly isolates storage dependency.
Pod survives NFS outage without restart, recovers instantly when NFS returns.
