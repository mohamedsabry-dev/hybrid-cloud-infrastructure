# TS-K8S-029 | 2026-04-13 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / Storage
Sub-techs: Readiness probe, Liveness probe, NFS storage failure detection,
           WordPress deployment, Service endpoints, Ingress NGINX
Environment: DEV k8s-dev cluster | k8s-worker1 | apps namespace
Re-opened: No

_____________________________________________________________________

[Issue Description]
WordPress pod remained in Service endpoints despite NFS storage failure.
~33% of user requests failed with timeout when routed to the pod with broken NFS.
Discovered during DR Test 3 — NAS Storage Outage (Scenario 1).

  Ingress logs showing failed requests to 10.244.62.14 (worker1 pod):
  20:01:40 → 10.244.62.14:80 → HTTP 499 → 4.993s timeout
  20:02:39 → 10.244.62.14:80 → HTTP 499 → 33.213s timeout
  20:34:15 → 10.244.62.14:80 → HTTP 499 → 2.216s timeout

_____________________________________________________________________

[Analysis]

# Initial Check Notes:

Check 1 — WordPress pod status during NFS outage:
  kubectl get pods -n apps -o wide
  Output:
    wordpress-79f66bd68b-2jh6q  2/2  Running  worker1  ← Still showing Ready!
    wordpress-79f66bd68b-sg58w  2/2  Running  worker2
    wordpress-79f66bd68b-dqstv  2/2  Running  worker3
  Pod on worker1 still reported as fully Ready despite NFS being unreachable.

Check 2 — Service endpoints:
  kubectl get endpoints wordpress -n apps
  Output:
    wordpress  10.244.207.117:80, 10.244.29.129:80, 10.244.62.14:80
               (worker2 - OK)     (worker3 - OK)     (worker1 - BROKEN!)
  Broken pod still in endpoints → traffic routed to it → failures.

Check 3 — Readiness probe configuration:
  kubectl describe pod wordpress-79f66bd68b-2jh6q -n apps | grep -A5 "Readiness:"
  Output:
    Readiness: http-get http://:80/wp-includes/images/blank.gif
    delay=5s timeout=3s period=5s failure=3

  /wp-includes/ is baked into the container image (local filesystem).
  It is NOT on the NFS mount. Probe always passes regardless of NFS state.

Check 4 — Volume mounts:
  kubectl describe pod wordpress-79f66bd68b-2jh6q -n apps | grep -A5 "Mounts:"
  Output:
    /var/www/html/wp-content from wordpress-data (NFS)
  Only /wp-content is on NFS. /wp-includes/ is local in the image.

Check 5 — Why liveness probe is NOT the solution:
  Liveness fails → container restart on SAME node → NFS still broken
  → fails again → useless restart loop.
  Liveness restarts do not reschedule pods to different nodes.
  Readiness is the correct approach — removes pod from endpoints without restart.

Summary:
  Pod Ready status         2/2 during NFS outage        WRONG
  Service endpoints        broken pod included           WRONG
  Readiness probe path     /wp-includes/ (local)         ROOT CAUSE
  NFS mount path           /wp-content only              CONFIRMED
  Liveness for NFS check   useless restart loop          NOT THE FIX


# Suspected Root Cause
Readiness probe checked /wp-includes/images/blank.gif which is baked into the
container image (local filesystem), not on NFS. When NFS became unreachable,
the probe still passed — pod stayed in Service endpoints and continued receiving
traffic that would fail. Silent failure — pod looks healthy but cannot serve
requests that depend on NFS-backed content.


# More Checks Notes:
N/A — probe path vs NFS mount path confirmed the root cause.


# Suspected Solution
Change readiness probe to check a path on the NFS mount (/wp-content/index.php)
so it fails when storage is unavailable. Keep liveness probe on local path to
avoid useless restart loops.


# Test
Applied probe change, simulated NFS outage on worker1.

Command:
  ssh root@k8s-worker1 'ip link set eth1 down'
  kubectl get pods -n apps -o wide
  kubectl get endpoints wordpress -n apps

Result: PASS
  wordpress-...-pxlpm  1/2  Running  worker1  ← NOT READY (correct)
  endpoints: 10.244.207.88:80, 10.244.29.139:80  ← only healthy pods

Traffic test (20 requests):
  Before fix: 90% success, 10% timeout (HTTP 000)
  After fix:  100% success (HTTP 200)

_____________________________________________________________________

[Final Root Cause]
WordPress readiness probe checked /wp-includes/images/blank.gif — a file baked
into the container image on local filesystem, not on NFS. NFS mount path is
/var/www/html/wp-content only. When NFS became unreachable, the probe continued
passing because it only checked a local file. Pod stayed in Service endpoints
and received traffic that would time out waiting for NFS-backed responses.

_____________________________________________________________________

[Final Solution]
Changed readiness probe to check an NFS-mounted path.
Kept liveness probe on local path to avoid useless restart loops.

  Before (problematic):
    readinessProbe:
      httpGet:
        path: /wp-includes/images/blank.gif   ← local file, never detects NFS failure
        port: 80
      timeoutSeconds: 3

  After (fixed):
    readinessProbe:
      httpGet:
        path: /wp-content/index.php           ← on NFS mount, fails when NFS unreachable
        port: 80
      timeoutSeconds: 5                        ← longer timeout for NFS latency

    livenessProbe:
      httpGet:
        path: /wp-includes/images/blank.gif   ← local, pod stays alive (no restart loop)
        port: 80

  With failureThreshold: 3 and timeoutSeconds: 5, pod is removed from endpoints
  after 15 seconds of NFS failure — brief NFS slowdowns (false positives) mitigated.

File: kubernetes/dev/deployments/apps/wordpress/deployment.yaml
Applied to both dev and prod.

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Pod may be removed from endpoints during brief NFS slowdowns (false positive).
Mitigated by timeoutSeconds: 5 and failureThreshold: 3 (15s total before removal).

_____________________________________________________________________

[References]
- DR Test 3 — NAS Storage Outage — Scenario 1
- https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/

_____________________________________________________________________

[Draft Notes]

Design principle:
  Liveness probe  → check if process is alive (local file OK, no restart loop)
  Readiness probe → check if pod CAN serve requests (must include dependencies like storage)

Why this matters for DR:
  NFS storage failures should automatically divert traffic to healthy pods.
  Without proper readiness probes, users experience random failures with no
  automated recovery — operator must manually detect and delete the broken pod.

Verification commands:
  # Simulate NFS outage on worker1
  ssh root@k8s-worker1 'ip link set eth1 down'

  # Check pod becomes not ready
  kubectl get pods -n apps -o wide
  → should show 1/2 for affected pod

  # Check endpoints exclude broken pod
  kubectl get endpoints wordpress -n apps
  → broken pod IP should NOT appear