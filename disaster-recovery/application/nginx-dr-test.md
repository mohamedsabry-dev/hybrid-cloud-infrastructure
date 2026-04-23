# DR Test: NGINX Layer Failures
# Date: 2026-04-16
# Status: COMPLETED

---

## Executive Summary

Test NGINX resilience at both layers:
1. **External NGINX** (ex-nginx LXC) - SPOF for external traffic
2. **Ingress NGINX** (K8s pods) - internal traffic routing

---

## Environment

| Component | Details |
|-----------|---------|
| External NGINX | ex-nginx LXC (10.0.65.10) |
| Ingress NGINX | 3 pods in ingress-nginx namespace |
| Test App | WordPress (wordpress-dev.lab.local) |

---

## Test 1A: External NGINX Node Down (Complete Failure)

### Scope
Shutdown entire ex-nginx LXC node - traffic goes into void.

### Pre-Test Baseline
```bash
[root@ansible dev]# ssh root@ex-nginx 'uptime'
 22:17:56 up  2:16,  2 users,  load average: 1.26, 1.09, 1.27

[root@ansible dev]# curl -I http://wordpress-dev.lab.local
HTTP/1.1 200 OK
Server: nginx/1.26.3
Date: Thu, 16 Apr 2026 20:18:04 GMT
Content-Type: text/html; charset=UTF-8
```

### Test Execution
```bash
[root@ansible dev]# ssh root@ex-nginx 'poweroff'

[root@ansible dev]# curl -I http://wordpress-dev.lab.local --connect-timeout 5
curl: (7) Failed to connect to wordpress-dev.lab.local port 80 after 3108 ms: Could not connect to server

[root@ansible dev]# ping wordpress-dev.lab.local
PING wordpress-dev.lab.local (10.0.65.10) 56(84) bytes of data.
From _gateway (10.0.63.1) icmp_seq=1 Destination Host Unreachable
From _gateway (10.0.63.1) icmp_seq=2 Destination Host Unreachable
From _gateway (10.0.63.1) icmp_seq=3 Destination Host Unreachable
^C
--- wordpress-dev.lab.local ping statistics ---
4 packets transmitted, 0 received, +3 errors, 100% packet loss, time 3050ms
```

### Result: PASS
- External access: **DOWN** (ERR_ADDRESS_UNREACHABLE)
- Traffic: Goes into void (Destination Host Unreachable)
- Connection timeout: ~3 seconds
- **SPOF CONFIRMED** - single node failure = complete external outage

---

## Test 1B: External NGINX Service Down (Node Up)

### Scope
Node running but nginx service stopped - different failure mode.

### Pre-Test Baseline (After Node Recovery)
```bash
[root@ansible dev]# ssh root@ex-nginx 'uptime'
 22:21:36 up 0 min,  2 users,  load average: 1.03, 1.07, 1.22

[root@ansible dev]# curl -I http://wordpress-dev.lab.local
HTTP/1.1 200 OK
Server: nginx/1.26.3
Date: Thu, 16 Apr 2026 20:21:44 GMT
```

### Test Execution
```bash
[root@ansible dev]# ssh root@ex-nginx 'systemctl stop nginx'

[root@ansible dev]# curl -I http://wordpress-dev.lab.local
curl: (7) Failed to connect to wordpress-dev.lab.local port 80 after 6 ms: Could not connect to server

# Ping WORKS (node is up)
[root@ansible dev]# ping wordpress-dev.lab.local
PING wordpress-dev.lab.local (10.0.65.10) 56(84) bytes of data.
64 bytes from 10.0.65.10: icmp_seq=1 ttl=63 time=2.81 ms
64 bytes from 10.0.65.10: icmp_seq=2 ttl=63 time=2.79 ms

# Port check - Connection REFUSED (not timeout)
[root@ansible dev]# nc -zv wordpress-dev.lab.local 80
Ncat: Version 7.92 ( https://nmap.org/ncat )
Ncat: Connection refused.
```

### Result: PASS
- Node: **UP** (ping works)
- Nginx: **DOWN** (service stopped)
- External access: **Connection refused** (6ms - fast failure)
- Key difference from node down: **Fast failure** vs timeout

### Failure Mode Comparison
| Scenario | Ping | Port 80 | Curl Response Time |
|----------|------|---------|-------------------|
| Node DOWN | Destination Host Unreachable | N/A | ~3000ms timeout |
| Node UP, Service DOWN | Works | Connection refused | ~6ms fast fail |

### Logs Analysis
```bash
# journalctl shows clean shutdown (not crash)
[root@ex-nginx ~]# journalctl -u nginx
Apr 16 22:20:54 ex-nginx systemd[1]: Starting nginx.service...
Apr 16 22:20:55 ex-nginx nginx[253]: nginx: configuration file test is successful
Apr 16 22:20:55 ex-nginx systemd[1]: Started nginx.service
Apr 16 22:21:54 ex-nginx systemd[1]: Stopping nginx.service...
Apr 16 22:21:54 ex-nginx systemd[1]: nginx.service: Deactivated successfully.
Apr 16 22:21:54 ex-nginx systemd[1]: Stopped nginx.service.

# error.log shows graceful shutdown via SIGQUIT from systemd (PID 1)
[root@ex-nginx ~]# tail /var/log/nginx/error.log
2026/04/16 22:21:54 [notice] 278#278: signal 3 (SIGQUIT) received from 1, shutting down
2026/04/16 22:21:54 [notice] 279#279: gracefully shutting down
2026/04/16 22:21:54 [notice] 279#279: exiting
2026/04/16 22:21:54 [notice] 279#279: exit
2026/04/16 22:21:54 [notice] 278#278: worker process 279 exited with code 0
2026/04/16 22:21:54 [notice] 278#278: exit
```

### Note on Logs
- `signal 3 (SIGQUIT)` = graceful shutdown signal from systemd
- `received from 1` = PID 1 (systemd) sent the stop signal
- `exited with code 0` = clean shutdown, no crash
- For crash/error scenarios, look for `[error]` or `[crit]` entries

### Troubleshooting Commands Reference
```bash
# Check for errors in nginx logs
grep -E "\[error\]|\[crit\]|\[alert\]|\[emerg\]" /var/log/nginx/error.log
# Result: (empty - no errors, clean shutdown)

# Check systemd service status
systemctl status nginx --no-pager -l
# Result: All processes exited with code 0 (SUCCESS)

# Check kernel logs for OOM
dmesg | grep -i "nginx\|oom"
# Result: "Operation not permitted" - LXC unprivileged container cannot read kernel buffer
```

### LXC Container Limitation
- `dmesg` not available in unprivileged LXC containers
- Cannot check for OOM kills or kernel-level issues from inside container
- For kernel-level troubleshooting, check Proxmox host: `pct exec <id> -- dmesg` or host's `/var/log/messages`

### Why No Errors in Logs
Clean shutdown via `systemctl stop` = no errors recorded.
Errors only appear when:
- Config syntax error (nginx -t fails)
- Port already in use
- Permission denied
- Upstream unreachable
- OOM kill (kernel level)

---

## Test 1C: Config Error - Reload Failure

### Scope
Introduce config syntax error and attempt reload - see error logging behavior.

### Test Execution
```bash
# Add invalid directive to config
[root@ex-nginx ~]# echo "invalid_directive;" >> /etc/nginx/nginx.conf

# Try reload (will fail)
[root@ex-nginx ~]# systemctl reload nginx
Job for nginx.service failed.
See "systemctl status nginx.service" and "journalctl -xeu nginx.service" for details.
```

### Error Evidence

**systemctl status shows:**
```
Process: 647 ExecReload=/usr/sbin/nginx -s reload (code=exited, status=1/FAILURE)
Apr 16 22:35:24 ex-nginx nginx[647]: nginx: [emerg] unknown directive "invalid_directive" in /etc/nginx/nginx.conf:53
Apr 16 22:35:24 ex-nginx systemd[1]: nginx.service: Control process exited, code=exited, status=1/FAILURE
Apr 16 22:35:24 ex-nginx systemd[1]: Reload failed for nginx.service
```

**journalctl -u nginx shows:**
```
Apr 16 22:35:24 ex-nginx nginx[647]: nginx: [emerg] unknown directive "invalid_directive" in /etc/nginx/nginx.conf:53
Apr 16 22:35:24 ex-nginx systemd[1]: nginx.service: Control process exited, code=exited, status=1/FAILURE
Apr 16 22:35:24 ex-nginx systemd[1]: Reload failed for nginx.service
```

**/var/log/nginx/error.log shows:**
```
2026/04/16 22:35:24 [emerg] 647#647: unknown directive "invalid_directive" in /etc/nginx/nginx.conf:53
```

**/var/log/messages shows:**
```
Apr 16 22:35:24 ex-nginx nginx[647]: nginx: [emerg] unknown directive "invalid_directive" in /etc/nginx/nginx.conf:53
Apr 16 22:35:24 ex-nginx systemd[1]: nginx.service: Control process exited, code=exited, status=1/FAILURE
Apr 16 22:35:24 ex-nginx systemd[1]: Reload failed for nginx.service
```

### Result: PASS (Graceful Failure)
- Reload: **FAILED** (config error detected)
- Service: **STILL RUNNING** (old config preserved)
- Traffic: **NOT AFFECTED** (nginx keeps serving with previous valid config)

### Key Finding: Graceful Reload Failure
```
┌─────────────────────────────────────────────────────────────────┐
│  NGINX RELOAD SAFETY: Config error does NOT crash the service  │
│  - nginx -t runs before applying new config                    │
│  - If test fails, old config remains active                    │
│  - Service continues serving traffic                           │
└─────────────────────────────────────────────────────────────────┘
```

### Error Log Levels Reference
| Level | Meaning | Example |
|-------|---------|---------|
| [emerg] | Emergency - cannot start/reload | Config syntax error |
| [alert] | Alert - immediate action needed | Cannot open error log |
| [crit] | Critical | Socket/memory failures |
| [error] | Error - request failed | Upstream timeout |
| [warn] | Warning - non-fatal | Buffer too small |
| [notice] | Normal significant event | Start/stop/reload |
| [info] | Informational | Client closed connection |

---

## Test 2A: Ingress NGINX Partial Failure (1 of 3 pods)

### Scope
Kill 1 ingress-nginx pod, verify service continuity via remaining pods.

### Analysis
**SKIPPED** - Not meaningful because:
- 3 replicas provide built-in HA
- External nginx load balances to all workers via NodePort
- kube-proxy routes to any healthy ingress pod
- Killing 1 pod = traffic shifts instantly, no visible impact

---

## Test 2B: Ingress NGINX Full Failure (3 of 3 pods)

### Scope
Kill all ingress-nginx pods simultaneously - measure outage duration.

### Pre-Test Baseline
```bash
[k8s_admin@k8s-master1 ~]$ kubectl get pods -n ingress-nginx -o wide
NAME                                        READY   STATUS    RESTARTS        AGE    IP               NODE
ingress-nginx-controller-7d4c58858f-4mjnt   1/1     Running   11 (160m ago)   7d6h   10.244.207.65    k8s-worker2.lab.local
ingress-nginx-controller-7d4c58858f-pfpjh   1/1     Running   13 (160m ago)   7d6h   10.244.62.14     k8s-worker1.lab.local
ingress-nginx-controller-7d4c58858f-wx4cv   1/1     Running   8 (160m ago)    5d7h   10.244.207.122   k8s-worker2.lab.local
```

### Test Execution
```bash
# Pre-delete - working
[root@ansible dev]# curl -I http://wordpress-dev.lab.local --connect-timeout 2
HTTP/1.1 200 OK

# Kill all 3 pods
[k8s_admin@k8s-master1 ~]$ kubectl delete pod -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
pod "ingress-nginx-controller-7d4c58858f-4mjnt" deleted
pod "ingress-nginx-controller-7d4c58858f-pfpjh" deleted
pod "ingress-nginx-controller-7d4c58858f-wx4cv" deleted

# During outage - 502 Bad Gateway (~17 seconds)
[root@ansible dev]# curl -I http://wordpress-dev.lab.local --connect-timeout 2
HTTP/1.1 502 Bad Gateway    # 20:51:08
HTTP/1.1 502 Bad Gateway    # 20:51:10
HTTP/1.1 502 Bad Gateway    # 20:51:14
HTTP/1.1 502 Bad Gateway    # 20:51:16
HTTP/1.1 502 Bad Gateway    # 20:51:25

# Pods recreated (~21 seconds)
[k8s_admin@k8s-master1 ~]$ kubectl get pods -n ingress-nginx -o wide
NAME                                        READY   STATUS    RESTARTS   AGE   IP              NODE
ingress-nginx-controller-7d4c58858f-c9wrl   1/1     Running   0          21s   10.244.29.170   k8s-worker3.lab.local
ingress-nginx-controller-7d4c58858f-d782c   1/1     Running   0          21s   10.244.29.156   k8s-worker3.lab.local
ingress-nginx-controller-7d4c58858f-lcxbl   1/1     Running   0          21s   10.244.62.9     k8s-worker1.lab.local
```

### Result: PASS
- Outage duration: **~17-20 seconds** (502 Bad Gateway)
- Recovery: **Automatic** via Deployment controller
- New pods: Scheduled on different workers

### Key Findings
```
┌─────────────────────────────────────────────────────────────────┐
│  INGRESS-NGINX FULL FAILURE:                                   │
│  - 502 Bad Gateway during outage (external nginx UP, backend DOWN)
│  - Auto-recovery in ~20 seconds                                 │
│  - No manual intervention needed                                │
│  - Deployment controller handles pod recreation                 │
└─────────────────────────────────────────────────────────────────┘
```

### 502 vs Connection Refused
| External NGINX state | Ingress state | User sees |
|---------------------|---------------|-----------|
| DOWN | Any | Connection timeout/refused |
| UP | DOWN | **502 Bad Gateway** |
| UP | UP | 200 OK |

### Result: PASS
- App: **DOWN** (~17-20 seconds)
- Recovery: **Auto** via Deployment controller
- All 3 pods: Restored automatically

### Recovery Verification
```bash
# Check all pods running
kubectl get pods -n ingress-nginx

# Check Flux status (optional)
flux get kustomization

# Verify access restored
curl -I http://wordpress-dev.lab.local
```

### Evidence
```
# (Record actual output here during test)
```

---

## Test 3: Ingress-NGINX Dynamic Backend & Endpoint Behavior

================================================================================
TEST RECORD: ingress-nginx Dynamic Backend & Endpoint Behavior
Date: 2026-04-16
Cluster: homelab k8s (3 masters / 3 workers)
Namespace: apps (WordPress), monitoring (Grafana), ingress-nginx
================================================================================

OBJECTIVE
---------
Verify that ingress-nginx dynamically updates its Lua backend table when
WordPress pods are scaled down and back up, without requiring an nginx reload.

--------------------------------------------------------------------------------
ENVIRONMENT
--------------------------------------------------------------------------------

Ingress Controller:
  Deployment:  ingress-nginx-controller
  Replicas:    3
  Version:     1.15.1
  Pods:
    ingress-nginx-controller-7d4c58858f-c9wrl
    ingress-nginx-controller-7d4c58858f-d782c
    ingress-nginx-controller-7d4c58858f-lcxbl

WordPress:
  Deployment:  wordpress
  Namespace:   apps
  Initial replicas: 3
  Managed by: Flux GitOps

Ingress Resource (ingress-wordpress):
  Host:       wordpress-dev.lab.local
  Class:      nginx
  Backend:    wordpress:80
  Annotations:
    nginx.ingress.kubernetes.io/affinity:                 cookie
    nginx.ingress.kubernetes.io/session-cookie-name:      wordpress-sticky
    nginx.ingress.kubernetes.io/session-cookie-expires:   172800
    nginx.ingress.kubernetes.io/session-cookie-max-age:   172800
    nginx.ingress.kubernetes.io/proxy-body-size:          500m

--------------------------------------------------------------------------------
BACKGROUND: ingress-nginx Backend Architecture
--------------------------------------------------------------------------------

ingress-nginx does NOT generate a static upstream block per backend service
(unlike traditional NGINX config). Instead it uses a single upstream:

    upstream upstream_balancer { ... }

All routing is handled at runtime by Lua code embedded in the controller.
Backend state (pod IPs, ports, affinity config) is stored in a Lua shared
dictionary, updated dynamically via an internal HTTP API on port 10246:

    GET http://localhost:10246/configuration/backends

The session-cookie-name annotation ("wordpress-sticky") is stored as a field
inside the backend entry's sessionAffinityConfig — it is not a separate
upstream. The controller intercepts requests and routes to the correct pod
using the cookie value, all without a nginx reload.

--------------------------------------------------------------------------------
PRE-TEST INVESTIGATION: Searching nginx.conf for Upstream Blocks
--------------------------------------------------------------------------------

Initial assumption was that ingress-nginx would have a static upstream block
per backend service in nginx.conf, similar to a traditional NGINX setup:

    upstream wordpress { server 10.244.x.x; server 10.244.x.x; }

Exec'd into controller pod to check:

  kubectl exec -it ingress-nginx-controller-7d4c58858f-d782c -n ingress-nginx -- sh

Searched nginx.conf for upstream definitions:

  cat /etc/nginx/nginx.conf | grep upstream

Relevant output:
  upstream upstream_balancer {
  set $proxy_upstream_name "upstream-default-backend";
  set $proxy_upstream_name "monitoring-kube-prometheus-stack-grafana-80";
  set $proxy_upstream_name "apps-wordpress-80";
  proxy_pass http://upstream_balancer;
  ...

Finding: There is only ONE upstream block — upstream_balancer — shared by all
backends. The per-backend names (apps-wordpress-80, etc.) appear only as Lua
variable assignments ($proxy_upstream_name), not as separate upstream blocks.
No pod IPs anywhere in the config file.

Directory listing confirmed no additional upstream config files:
  /etc/nginx/
    fastcgi.conf     lua/         mime.types    nginx.conf
    fastcgi_params   modsecurity/ modules/      template/
    ...

Conclusion: Pod IPs are not stored in nginx.conf at all. The correct place to
look is the Lua runtime backend table, queried via:

  curl -s http://localhost:10246/configuration/backends

This is the live in-memory equivalent of all upstream blocks, maintained
dynamically by the controller without requiring nginx reloads.

--------------------------------------------------------------------------------
STEP 1: VERIFY INITIAL STATE (3 REPLICAS)
--------------------------------------------------------------------------------

Command:
  kubectl get pods -n apps -o wide

Output:
  wordpress-5f649b595f-2kdks   2/2 Running   10.244.62.5     k8s-worker1
  wordpress-5f649b595f-n65mm   2/2 Running   10.244.207.68   k8s-worker2
  wordpress-5f649b595f-tpzrj   2/2 Running   10.244.29.174   k8s-worker3

Command:
  kubectl get endpoints wordpress -n apps

Output:
  wordpress   10.244.207.68:80, 10.244.29.174:80, 10.244.62.5:80

Command:
  kubectl exec -n ingress-nginx ingress-nginx-controller-7d4c58858f-c9wrl -- \
    curl -s http://localhost:10246/configuration/backends

Full Raw Output:
  [{"name":"apps-wordpress-80","service":{"metadata":{},"spec":{"ports":[{"name":"http","protocol":"TCP","port":80,"targetPort":80}],"selector":{"app":"wordpress"},"clusterIP":"10.99.113.66","clusterIPs":["10.99.113.66"],"type":"ClusterIP","sessionAffinity":"None","ipFamilies":["IPv4"],"ipFamilyPolicy":"SingleStack","internalTrafficPolicy":"Cluster"},"status":{"loadBalancer":{}}},"port":80,"sslPassthrough":false,"endpoints":[{"address":"10.244.207.68","port":"80"},{"address":"10.244.62.5","port":"80"},{"address":"10.244.29.174","port":"80"}],"sessionAffinityConfig":{"name":"cookie","mode":"","cookieSessionAffinity":{"name":"wordpress-sticky","expires":"172800","maxage":"172800","locations":{"wordpress-dev.lab.local":["/"]}}},  "upstreamHashByConfig":{"upstream-hash-by-subset-size":3},"noServer":false,"trafficShapingPolicy":{"weight":0,"weightTotal":0,"header":"","headerValue":"","headerPattern":"","cookie":""}},{"name":"monitoring-kube-prometheus-stack-grafana-80","service":{"metadata":{},"spec":{"ports":[{"name":"http-web","protocol":"TCP","port":80,"targetPort":"grafana"}],"selector":{"app.kubernetes.io/instance":"kube-prometheus-stack","app.kubernetes.io/name":"grafana"},"clusterIP":"10.97.242.133","clusterIPs":["10.97.242.133"],"type":"ClusterIP","sessionAffinity":"None","ipFamilies":["IPv4"],"ipFamilyPolicy":"SingleStack","internalTrafficPolicy":"Cluster"},"status":{"loadBalancer":{}}},"port":80,"sslPassthrough":false,"endpoints":[{"address":"10.244.29.171","port":"3000"},{"address":"10.244.207.80","port":"3000"},{"address":"10.244.62.37","port":"3000"}],"sessionAffinityConfig":{"name":"","mode":"","cookieSessionAffinity":{"name":""}},"upstreamHashByConfig":{"upstream-hash-by-subset-size":3},"noServer":false,"trafficShapingPolicy":{"weight":0,"weightTotal":0,"header":"","headerValue":"","headerPattern":"","cookie":""}},{"name":"upstream-default-backend","port":0,"sslPassthrough":false,"endpoints":[{"address":"127.0.0.1","port":"8181"}],"sessionAffinityConfig":{"name":"","mode":"","cookieSessionAffinity":{"name":""}},"upstreamHashByConfig":{},"noServer":false,"trafficShapingPolicy":{"weight":0,"weightTotal":0,"header":"","headerValue":"","headerPattern":"","cookie":""}}]

  Extracted — apps-wordpress-80 backend (3 backends total in output):
  >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
  "name": "apps-wordpress-80"
  "endpoints": [
    { "address": "10.244.207.68", "port": "80" },   <- worker2
    { "address": "10.244.62.5",   "port": "80" },   <- worker1
    { "address": "10.244.29.174", "port": "80" }    <- worker3
  ]
  "sessionAffinityConfig": {
    "name": "cookie",
    "cookieSessionAffinity": {
      "name":    "wordpress-sticky",
      "expires": "172800",
      "maxage":  "172800",
      "locations": { "wordpress-dev.lab.local": ["/"] }
    }
  }
  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

Result: PASS — Lua backend matches Kubernetes endpoints exactly.

--------------------------------------------------------------------------------
STEP 2: SCALE DOWN TO 2 REPLICAS
--------------------------------------------------------------------------------

Command:
  kubectl scale deployment wordpress -n apps --replicas=2

Observation:
  Pod wordpress-5f649b595f-2kdks (10.244.62.5) terminated.

Command:
  kubectl get endpoints wordpress -n apps

Output:
  wordpress   10.244.207.68:80, 10.244.29.174:80

Command:
  kubectl exec -n ingress-nginx ingress-nginx-controller-7d4c58858f-c9wrl -- \
    curl -s http://localhost:10246/configuration/backends

Full Raw Output:
  [{"name":"apps-wordpress-80","service":{"metadata":{},"spec":{"ports":[{"name":"http","protocol":"TCP","port":80,"targetPort":80}],"selector":{"app":"wordpress"},"clusterIP":"10.99.113.66","clusterIPs":["10.99.113.66"],"type":"ClusterIP","sessionAffinity":"None","ipFamilies":["IPv4"],"ipFamilyPolicy":"SingleStack","internalTrafficPolicy":"Cluster"},"status":{"loadBalancer":{}}},"port":80,"sslPassthrough":false,"endpoints":[{"address":"10.244.207.68","port":"80"},{"address":"10.244.29.174","port":"80"}],"sessionAffinityConfig":{"name":"cookie","mode":"","cookieSessionAffinity":{"name":"wordpress-sticky","expires":"172800","maxage":"172800","locations":{"wordpress-dev.lab.local":["/"]}}}, "upstreamHashByConfig":{"upstream-hash-by-subset-size":3},"noServer":false,"trafficShapingPolicy":{"weight":0,"weightTotal":0,"header":"","headerValue":"","headerPattern":"","cookie":""}},{"name":"monitoring-kube-prometheus-stack-grafana-80","service":{"metadata":{},"spec":{"ports":[{"name":"http-web","protocol":"TCP","port":80,"targetPort":"grafana"}],"selector":{"app.kubernetes.io/instance":"kube-prometheus-stack","app.kubernetes.io/name":"grafana"},"clusterIP":"10.97.242.133","clusterIPs":["10.97.242.133"],"type":"ClusterIP","sessionAffinity":"None","ipFamilies":["IPv4"],"ipFamilyPolicy":"SingleStack","internalTrafficPolicy":"Cluster"},"status":{"loadBalancer":{}}},"port":80,"sslPassthrough":false,"endpoints":[{"address":"10.244.29.171","port":"3000"},{"address":"10.244.207.80","port":"3000"},{"address":"10.244.62.37","port":"3000"}],"sessionAffinityConfig":{"name":"","mode":"","cookieSessionAffinity":{"name":""}},"upstreamHashByConfig":{"upstream-hash-by-subset-size":3},"noServer":false,"trafficShapingPolicy":{"weight":0,"weightTotal":0,"header":"","headerValue":"","headerPattern":"","cookie":""}},{"name":"upstream-default-backend","port":0,"sslPassthrough":false,"endpoints":[{"address":"127.0.0.1","port":"8181"}],"sessionAffinityConfig":{"name":"","mode":"","cookieSessionAffinity":{"name":""}},"upstreamHashByConfig":{},"noServer":false,"trafficShapingPolicy":{"weight":0,"weightTotal":0,"header":"","headerValue":"","headerPattern":"","cookie":""}}]

  Extracted — apps-wordpress-80 backend:
  >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
  "name": "apps-wordpress-80"
  "endpoints": [
    { "address": "10.244.207.68", "port": "80" },   <- worker2  STILL UP
    { "address": "10.244.29.174", "port": "80" }    <- worker3  STILL UP
    -- 10.244.62.5 (worker1) REMOVED --
  ]
  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

Result: PASS — 10.244.62.5 removed from both Kubernetes endpoints and Lua
backend immediately. No nginx reload triggered.

--------------------------------------------------------------------------------
STEP 3: FLUX RECONCILIATION RESTORES 3 REPLICAS
--------------------------------------------------------------------------------

Since replicas=3 is defined in Git and Flux is active, the deployment was
automatically reconciled back to 3 replicas shortly after the manual scale.

New pod scheduled: wordpress-5f649b595f-jwcnk

Pod startup sequence observed via kubectl get pods -n apps -w:
  0s    Pending
  0s    Init:0/2        <- Vault agent init container 1 starting
  1s    Init:1/2        <- Vault agent init container 2 starting
  4s    PodInitializing <- Both init containers completed, secrets injected
  5s    1/2 Running     <- Main wordpress container up, vault sidecar not yet ready
  11s   2/2 Running     <- Vault sidecar ready, pod passes readiness check

Note: The 2 init containers are the Vault agent injector pattern — secrets are
pulled from Vault and written to /vault/secrets/ before the main container
starts. The pod was NOT added to endpoints until 2/2 Ready at 11s, confirming
readiness gates work correctly.

Command:
  kubectl get endpoints wordpress -n apps

Output:
  wordpress   10.244.207.68:80, 10.244.29.174:80, 10.244.62.8:80
                                                   ^^^^^^^^^^^^^^
                                                   new pod IP

Command:
  kubectl exec -n ingress-nginx ingress-nginx-controller-7d4c58858f-c9wrl -- \
    curl -s http://localhost:10246/configuration/backends

Full Raw Output:
  [{"name":"apps-wordpress-80","service":{"metadata":{},"spec":{"ports":[{"name":"http","protocol":"TCP","port":80,"targetPort":80}],"selector":{"app":"wordpress"},"clusterIP":"10.99.113.66","clusterIPs":["10.99.113.66"],"type":"ClusterIP","sessionAffinity":"None","ipFamilies":["IPv4"],"ipFamilyPolicy":"SingleStack","internalTrafficPolicy":"Cluster"},"status":{"loadBalancer":{}}},"port":80,"sslPassthrough":false,"endpoints":[{"address":"10.244.207.68","port":"80"},{"address":"10.244.29.174","port":"80"},{"address":"10.244.62.8","port":"80"}],"sessionAffinityConfig":{"name":"cookie","mode":"","cookieSessionAffinity":{"name":"wordpress-sticky","expires":"172800","maxage":"172800","locations":{"wordpress-dev.lab.local":["/"]}}}, "upstreamHashByConfig":{"upstream-hash-by-subset-size":3},"noServer":false,"trafficShapingPolicy":{"weight":0,"weightTotal":0,"header":"","headerValue":"","headerPattern":"","cookie":""}},{"name":"monitoring-kube-prometheus-stack-grafana-80","service":{"metadata":{},"spec":{"ports":[{"name":"http-web","protocol":"TCP","port":80,"targetPort":"grafana"}],"selector":{"app.kubernetes.io/instance":"kube-prometheus-stack","app.kubernetes.io/name":"grafana"},"clusterIP":"10.97.242.133","clusterIPs":["10.97.242.133"],"type":"ClusterIP","sessionAffinity":"None","ipFamilies":["IPv4"],"ipFamilyPolicy":"SingleStack","internalTrafficPolicy":"Cluster"},"status":{"loadBalancer":{}}},"port":80,"sslPassthrough":false,"endpoints":[{"address":"10.244.29.171","port":"3000"},{"address":"10.244.207.80","port":"3000"},{"address":"10.244.62.37","port":"3000"}],"sessionAffinityConfig":{"name":"","mode":"","cookieSessionAffinity":{"name":""}},"upstreamHashByConfig":{"upstream-hash-by-subset-size":3},"noServer":false,"trafficShapingPolicy":{"weight":0,"weightTotal":0,"header":"","headerValue":"","headerPattern":"","cookie":""}},{"name":"upstream-default-backend","port":0,"sslPassthrough":false,"endpoints":[{"address":"127.0.0.1","port":"8181"}],"sessionAffinityConfig":{"name":"","mode":"","cookieSessionAffinity":{"name":""}},"upstreamHashByConfig":{},"noServer":false,"trafficShapingPolicy":{"weight":0,"weightTotal":0,"header":"","headerValue":"","headerPattern":"","cookie":""}}]

  Extracted — apps-wordpress-80 backend:
  >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
  "name": "apps-wordpress-80"
  "endpoints": [
    { "address": "10.244.207.68", "port": "80" },   <- worker2  STILL UP
    { "address": "10.244.29.174", "port": "80" },   <- worker3  STILL UP
    { "address": "10.244.62.8",   "port": "80" }    <- worker1  NEW POD IP
  ]
  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

Result: PASS — New pod IP registered in Lua backend dynamically. No nginx
reload required. Readiness gate correctly held the pod out of rotation until
both containers were ready.

--------------------------------------------------------------------------------
FINDINGS SUMMARY
--------------------------------------------------------------------------------

1. Dynamic backend updates confirmed — ingress-nginx Lua layer updates pod IPs
   in real time via the /configuration/backends API. No nginx reload is needed
   for endpoint changes.

2. Readiness gates work correctly — pods are withheld from the backend until
   all containers (including Vault sidecar) pass readiness checks.

3. Vault init containers add ~11s to pod startup — 4s for secret injection,
   then 7s until sidecar is fully ready. This is the minimum traffic gap on
   a new pod coming online.

4. Flux GitOps enforces desired state — manual scale-down was reconciled back
   to replicas=3 automatically. To make a persistent change, it must be
   committed to Git.

5. Session affinity (wordpress-sticky cookie) is embedded inside the
   apps-wordpress-80 backend entry — it is not a separate upstream block.
   The cookie name is purely a client-side routing hint handled by Lua.

--------------------------------------------------------------------------------
TOOLS USED
--------------------------------------------------------------------------------

  kubectl exec          -- access controller pod shell
  curl :10246/configuration/backends  -- query live Lua backend state
  kubectl get endpoints -- verify Kubernetes-side endpoint registration
  kubectl scale         -- trigger controlled pod removal
  kubectl get pods -w   -- observe pod lifecycle in real time

================================================================================
END OF TEST RECORD
================================================================================

---

## Test Summary Table

| Test | Scenario | Expected App Status | Recovery Method | Actual Result |
|------|----------|---------------------|-----------------|---------------|
| 1A | External NGINX node down | DOWN | Start LXC | **PASS** - SPOF confirmed, ~3s timeout |
| 1B | External NGINX service down | DOWN | systemctl start | **PASS** - Fast fail (~6ms) |
| 1C | Config error on reload | UP (old config) | Fix config | **PASS** - Graceful failure |
| 2A | 1/3 ingress pods killed | UP | Auto (~seconds) | **SKIPPED** - Not meaningful (HA) |
| 2B | 3/3 ingress pods killed | DOWN (~20s) | Auto via Deployment | **PASS** - 502 for ~17-20s |
| 3 | Dynamic backend update | UP | Auto (Lua update) | **PASS** - No reload needed |

---

## Recovery Commands Quick Reference

```bash
# External NGINX
ssh root@ex-nginx 'systemctl start nginx'

# Force ingress pod recreation
kubectl rollout restart deployment -n ingress-nginx ingress-nginx-controller

# Check all layers
curl -I http://wordpress-dev.lab.local
kubectl get pods -n ingress-nginx
ssh root@ex-nginx 'systemctl status nginx'
```

---

## Notes

- External NGINX is intentional SPOF (single entry point)
- Future consideration: Add HA for external nginx (keepalived + VIP)
- Ingress NGINX has built-in HA (3 replicas)

---

## Related: Endpoint Removal via Readiness Probe

When a backend pod becomes unhealthy, traffic should automatically divert away from it.
This is controlled by Kubernetes readiness probes and endpoint management.

### How It Works

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  READINESS PROBE → ENDPOINT REMOVAL → TRAFFIC DIVERSION                    │
│                                                                             │
│  1. Pod readiness probe fails                                               │
│  2. Kubelet marks pod as NOT READY                                          │
│  3. Endpoints controller removes pod IP from Service endpoints              │
│  4. kube-proxy updates iptables/IPVS rules                                  │
│  5. Ingress-nginx stops forwarding to that pod                              │
│  6. External nginx (upstream via NodePort) only hits healthy pods           │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Example: WordPress Readiness Probe Fix

From NFS DR test (`single-worker-nfs-down.md`), the readiness probe was fixed to detect storage failures:

```yaml
# BEFORE (problematic):
readinessProbe:
  httpGet:
    path: /wp-includes/images/blank.gif  # Local file - doesn't detect NFS failure

# AFTER (fixed):
readinessProbe:
  httpGet:
    path: /wp-content/index.php  # On NFS mount - detects storage failure
  timeoutSeconds: 5              # Longer timeout for NFS latency
```

### Validation Results

| Metric | Before Fix | After Fix |
|--------|------------|-----------|
| Broken pod status | 2/2 Ready (wrong) | 1/2 Ready (correct) |
| Endpoints | 3 pods (broken included) | 2 pods (healthy only) |
| Traffic success | ~90% (timeouts) | **100%** ✅ |

### Why Readiness (Not Liveness) for Endpoint Removal

| Probe Type | On Failure | Use Case |
|------------|-----------|----------|
| **Readiness** | Pod removed from endpoints | Backend health (NFS, DB connection) |
| **Liveness** | Container restart on SAME node | Process crash recovery |

Liveness probe failure → container restart on same node → if storage still broken → restart fails again → useless loop.
Readiness probe failure → pod removed from endpoints → traffic diverts to healthy pods → graceful degradation.

---

## Related Documentation

- `network/ex-nginx/` - External nginx config
- `kubernetes/dev/deployments/infrastructure/ingress/` - Ingress helm release
- `disaster-recovery/single-worker-nfs-down.md` - NFS failure test with readiness probe fix details
