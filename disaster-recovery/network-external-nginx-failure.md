DR Test: External NGINX Failure (LXC)
Date: 2026-04-16
Result: PASS
_____________________________________________________________________

[Info]
Domain: Network / Reverse Proxy / LXC
Environment: DEV — ex-nginx LXC (10.0.65.10) | Proxmox
Triggered by: External nginx is a known SPOF — need to document the
  failure modes and how they look from the user side

_____________________________________________________________________

[Planned Scope]

Test 3 failure scenarios on the external nginx LXC:
1. Node completely down (poweroff)
2. Node up but nginx service stopped
3. Config error during reload

Components expected to be affected: all external traffic to WordPress
(and anything else behind this reverse proxy)

_____________________________________________________________________

[Pre-State]

ex-nginx LXC running, nginx serving, WordPress accessible:
```
curl -I http://wordpress-dev.lab.local
HTTP/1.1 200 OK
Server: nginx/1.26.3
```

_____________________________________________________________________

[Test 1.1 — Node down (poweroff)]

Action:
  ```
  ssh root@ex-nginx 'poweroff'
  ```

What happened:
  - curl: failed to connect after ~3000ms timeout
  - ping: "Destination Host Unreachable" from gateway
  - All external traffic dead — node gone from network entirely

What this tells me:
  SPOF confirmed. Single LXC down = complete external outage. No
  failover, no graceful degradation. Traffic goes into void until
  the node is manually started.

_____________________________________________________________________

[Test 1.2 — Service down (node still up)]

Why this test: different failure mode — node reachable but nginx process
  stopped. Wanted to see how the error looks differently.

Action:
  ```
  ssh root@ex-nginx 'systemctl stop nginx'
  ```

What happened:
  - curl: "Connection refused" in ~6ms (fast fail)
  - ping: works (node is up)
  - nc port check: "Connection refused" (port 80 not listening)

  Shutdown was clean — SIGQUIT from systemd, worker exited code 0.

What this tells me:
  The difference matters for triage:

  | Scenario           | Ping                       | Port 80            | Response time |
  |--------------------|----------------------------|--------------------|---------------|
  | Node DOWN          | Destination Host Unreachable | N/A               | ~3000ms       |
  | Service DOWN       | Works                      | Connection refused | ~6ms          |

  Fast "connection refused" = node is up, process is dead. Slow timeout =
  node itself is gone. You can tell which layer broke from the error alone.

_____________________________________________________________________

[Test 1.3 — Config error on reload]

Why this test: what happens if someone pushes a bad config and reloads?

Action:
  ```
  echo "invalid_directive;" >> /etc/nginx/nginx.conf
  systemctl reload nginx
  ```

What happened:
  - Reload failed with [emerg] in error.log:
    ```
    nginx: [emerg] unknown directive "invalid_directive" in /etc/nginx/nginx.conf:53
    ```
  - Service: STILL RUNNING on old config
  - Traffic: NOT AFFECTED

What this tells me:
  nginx runs `nginx -t` before applying new config on reload. If the test
  fails, old config stays active. Service never goes down. This is a safety
  net against bad config pushes — the worst case is "reload failed" in the
  logs, not an outage.

  Note: this only applies to `reload`. A full `restart` with bad config
  WILL kill the service.

_____________________________________________________________________

[Recovery]

All scenarios — single command:
  ```
  ssh root@ex-nginx 'systemctl start nginx'
  ```
  For node down: start the LXC from Proxmox first.

_____________________________________________________________________

[Findings]

1. External nginx is a confirmed SPOF. Single node or service failure =
   complete external outage. No auto-recovery. This is by design for now
   (single entry point), but keepalived + VIP is the obvious HA path if
   needed. Also planning a Lambda + CloudWatch trigger that calls the
   Proxmox API to auto-restart/reset the LXC if it goes down — part of
   a broader on-prem auto-recovery idea using AWS as the control plane.

2. Failure mode tells you the layer. Timeout = node gone. Connection
   refused = node up, process dead. 502 = nginx up, backend (ingress)
   dead. Useful for quick triage without SSH'ing into anything.

3. Config reload is safe. Bad config doesn't kill running service. Only
   a full restart with broken config causes an outage.

4. LXC limitation: dmesg not available in unprivileged containers. For
   OOM or kernel-level issues, must check from Proxmox host directly.

_____________________________________________________________________

[References]

- network/ex-nginx/ — External nginx config files
- app-ingress-nginx-failover.md — Ingress NGINX (K8s layer) failure tests
