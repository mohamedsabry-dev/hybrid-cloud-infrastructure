# DR Test: NGINX Layer Failures
# Date: 2026-04-16
# Status: IN PROGRESS

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

### Pre-Test Baseline
```bash
# Get ingress pods
kubectl get pods -n ingress-nginx -o wide

# Check which worker each pod is on
kubectl get pods -n ingress-nginx -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\n"}{end}'
```

### Test Execution
```bash
# Kill one pod (replace with actual pod name)
kubectl delete pod -n ingress-nginx <pod-name>

# Watch recovery
kubectl get pods -n ingress-nginx -w

# Test access during recovery
curl -I http://wordpress-dev.lab.local
```

### Expected Result
- App: **UP** (2 remaining pods handle traffic)
- Recovery: **Auto** (new pod scheduled in seconds)
- Traffic: Shifts to surviving pods

### Evidence
```
# (Record actual output here during test)
```

---

## Test 2B: Ingress NGINX Full Failure (3 of 3 pods)

### Scope
Kill all ingress-nginx pods, measure recovery time.

### Pre-Test Baseline
```bash
# Get all ingress pods
kubectl get pods -n ingress-nginx

# Check deployment config
kubectl get deployment -n ingress-nginx
```

### Test Execution
```bash
# Kill ALL pods
kubectl delete pod -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# Record timestamp
date

# Watch recovery
kubectl get pods -n ingress-nginx -w

# Test access (should fail briefly)
curl -I http://wordpress-dev.lab.local --connect-timeout 5
```

### Expected Result
- App: **DOWN** (briefly, ~10-30 seconds)
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

## Test Summary Table

| Test | Scenario | Expected App Status | Recovery Method | Actual Result |
|------|----------|---------------------|-----------------|---------------|
| 1A | External NGINX node down | DOWN | Start LXC | **PASS** - SPOF confirmed, ~3s timeout |
| 1B | External NGINX service down | DOWN | systemctl start | **PASS** - Fast fail (~6ms) |
| 1C | Config error on reload | UP (old config) | Fix config | **PASS** - Graceful failure |
| 2A | 1/3 ingress pods killed | UP | Auto (~seconds) | PENDING |
| 2B | 3/3 ingress pods killed | DOWN (~30s) | Auto via Deployment | PENDING |

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

## Related Documentation

- `network/ex-nginx/` - External nginx config
- `kubernetes/dev/deployments/infrastructure/ingress/` - Ingress helm release
