# TS-K8S-029 | 2026-04-13 | RESOLVED

## 1. Context
- System: Kubernetes / WordPress / NFS Storage / Readiness Probes
- Environment: DEV (k8s-worker1.lab.local)
- Related components: WordPress Deployment, NFS CSI, Ingress NGINX, Service Endpoints
- Discovered during: DR Test 3 - NAS Storage Outage (Scenario 1)

## 2. Issue
- Symptom: WordPress pod remained in Service endpoints despite NFS storage failure
- Impact: ~33% of user requests failed with timeout when routed to pod with broken NFS
- Error: `HTTP 499` (client timeout) in ingress-nginx logs for requests to affected pod

**Traffic routing during NFS outage:**
```
Request 5: HTTP 000 - 3.002s  ← TIMEOUT - hit broken pod
```

**Ingress logs showing failed requests:**
```
20:01:40 → 10.244.62.14:80 → HTTP 499 → 4.993s timeout
20:02:39 → 10.244.62.14:80 → HTTP 499 → 33.213s timeout
20:34:15 → 10.244.62.14:80 → HTTP 499 → 2.216s timeout
```

## 3. Analysis

**Check 1: WordPress Pod Status During NFS Outage**
```bash
kubectl get pods -n apps -o wide
```
```
wordpress-79f66bd68b-2jh6q   2/2   Running   worker1  ← Still showing 2/2 Ready!
wordpress-79f66bd68b-sg58w   2/2   Running   worker2
wordpress-79f66bd68b-dqstv   2/2   Running   worker3
```
Finding: Pod on worker1 still reported as fully Ready despite NFS being unreachable. **PROBLEM** ✗

---

**Check 2: Service Endpoints**
```bash
kubectl get endpoints wordpress -n apps
```
```
wordpress   10.244.207.117:80,10.244.29.129:80,10.244.62.14:80
            (worker2)          (worker3)          (worker1-broken!)
```
Finding: Broken pod still in endpoints → traffic routed to it → failures. **PROBLEM** ✗

---

**Check 3: Readiness Probe Configuration**
```bash
kubectl describe pod wordpress-79f66bd68b-2jh6q -n apps | grep -A5 "Readiness:"
```
```yaml
Readiness:
  http-get http://:80/wp-includes/images/blank.gif
  delay=5s timeout=3s period=5s #success=1 #failure=3
```
Finding: Readiness probe checks `/wp-includes/images/blank.gif`. **ROOT CAUSE IDENTIFIED** ✗

---

**Check 4: Volume Mounts**
```bash
kubectl describe pod wordpress-79f66bd68b-2jh6q -n apps | grep -A5 "Mounts:"
```
```
Mounts:
  /var/www/html/wp-content from wordpress-data (NFS)
```
Finding: Only `/wp-content` is on NFS. The probe path `/wp-includes/` is in container image (local). ✗

---

**Check 5: Why Liveness Probe Isn't The Solution**
```
Liveness fails → Container restart on SAME node → NFS still broken → Fails again → Useless restart loop
```
Finding: Liveness probe restarts don't reschedule pods to different nodes. Readiness is correct approach. ✓

---

**Findings Summary:**
```
+---------------------------+----------------------------------+------------+
| Check                     | Finding                          | Status     |
+---------------------------+----------------------------------+------------+
| Pod Ready status          | 2/2 during NFS outage            | WRONG      |
| Service endpoints         | Broken pod included              | WRONG      |
| Readiness probe path      | /wp-includes/ (local, not NFS)   | ROOT CAUSE |
| NFS mount path            | /var/www/html/wp-content only    | CONFIRMED  |
| Liveness for NFS check    | Would cause useless restart loop | NOT FIX    |
+---------------------------+----------------------------------+------------+
```

## 4. Root Cause
> WordPress readiness probe checked `/wp-includes/images/blank.gif` which is baked into the container image (local filesystem), not on the NFS mount (`/var/www/html/wp-content`). When NFS became unreachable, the probe still passed because it checked a local file, causing the pod to remain in Service endpoints and receive traffic that would fail.

## 5. Solution
> Change readiness probe to check a path on the NFS mount so it fails when storage is unavailable.

**File:** `kubernetes/dev/deployments/apps/wordpress/deployment.yaml`

**Before (problematic):**
```yaml
readinessProbe:
  httpGet:
    path: /wp-includes/images/blank.gif  # Local file - doesn't detect NFS failure
    port: 80
  timeoutSeconds: 3
```

**After (fixed):**
```yaml
# Readiness checks NFS-mounted path to detect storage failures
readinessProbe:
  httpGet:
    path: /wp-content/index.php  # On NFS mount - detects storage failure
    port: 80
  timeoutSeconds: 5  # Longer timeout for NFS latency

# Keep liveness on local path - no useless restarts
livenessProbe:
  httpGet:
    path: /wp-includes/images/blank.gif  # Local - pod stays alive
    port: 80
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact:
  - Pod may be removed from endpoints during brief NFS slowdowns (false positive)
  - Mitigated by: `timeoutSeconds: 5` and `failureThreshold: 3` (15s total before removal)

## 7. Impact After Fix

**Pod status during NFS outage (CORRECT):**
```
wordpress-...-pxlpm   1/2   Running   worker1  ← NOT READY (correct!)
wordpress-...-mb4ql   2/2   Running   worker2
wordpress-...-484ht   2/2   Running   worker3
```

**Endpoints (broken pod REMOVED):**
```
wordpress   10.244.207.88:80,10.244.29.139:80  ← Only healthy pods!
```

**Traffic test (20 requests):**
```
Before fix: 90% success, 10% timeout (HTTP 000)
After fix:  100% success (HTTP 200)
```

## 8. Notes

**Why this matters for DR:**
- NFS storage failures should automatically divert traffic to healthy pods
- Without proper readiness probes, users experience random failures
- This is a "silent failure" - pod looks healthy but can't serve requests

**Design principle:**
- Liveness probe: Check if process is alive (local file OK)
- Readiness probe: Check if pod can serve requests (must include dependencies like storage)

**Verification command:**
```bash
# Simulate NFS outage on worker1
ssh root@k8s-worker1 'ip link set eth1 down'

# Check pod becomes not ready
kubectl get pods -n apps -o wide
# Should show 1/2 for affected pod

# Check endpoints
kubectl get endpoints wordpress -n apps
# Should NOT include broken pod
```

## 9. Workaround (if any)
> Manual removal from endpoints: `kubectl delete pod <broken-pod>` - but requires human detection.

## References
- DR Test 3 - NAS Storage Outage - Scenario 1
- [Kubernetes Probe Configuration](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
