DR Test: Single Worker NFS Interface Down
Date: 2026-04-13
Result: PASS + 2 FIXES APPLIED
_____________________________________________________________________

[Info]
Domain: NFS / Kubernetes / Storage Classes / Readiness Probes
Environment: DEV — 6-node cluster, NAS at 10.0.40.120, workers reach
  NAS via eth1 (10.0.40.x storage VLAN)
Triggered by: What happens when a single worker loses NFS connectivity
  while the rest of the cluster is healthy?

_____________________________________________________________________

[Planned Scope]

Take down eth1 (storage interface) on worker1 only. Observe which pods
are affected, whether traffic is still routed to broken pods, and how
the cluster recovers when the interface comes back.

worker1 NFS-dependent pods: WordPress (1 of 3 replicas), Grafana
(single replica), Alertmanager. Non-NFS pods on worker1: Flux
controllers, ingress-nginx, CSI controller (1 of 2).

_____________________________________________________________________

[Pre-State]

All 6 nodes Ready. NFS mounts healthy on all workers (soft mount,
timeo=30, retrans=3 for apps; hard mount for MariaDB on worker3).
WordPress: 3 replicas across all workers. MariaDB: worker3. Grafana:
single replica on worker1. CSI controllers: worker1 + worker2.

_____________________________________________________________________

[Test 1.1 — Take down eth1 on worker1]

Action:
  ```
  ip link set eth1 down
  ```

What happened:
  Grafana (single replica, worker1): hit CreateContainerError. Readiness
  failed → liveness failed → kubelet killed container → restart failed
  because kubelet couldn't stat the NFS volume mount. Stuck in
  CreateContainerError → CrashLoopBackOff loop. Grafana completely down
  (503 for all users).

  WordPress (worker1 pod): stayed 2/2 Running — and that was the
  problem. Readiness probe checked /wp-includes/images/blank.gif
  (baked into container image, not on NFS). NFS was dead but probe
  passed → pod stayed in endpoints → ingress routed traffic to it →
  users hit timeouts.

  ```
  Request 5: HTTP 000 - 3.002s  ← hit worker1 (broken NFS)
  ```

  Ingress error logs confirmed traffic still hitting the broken pod:
  ```
  20:01:40 → 10.244.62.14:80 → HTTP 499 → 4.993s (client timeout)
  20:02:39 → 10.244.62.14:80 → HTTP 499 → 33.213s
  ```

  ~33% of requests were failing — 1 broken pod out of 3 in endpoints.

  MariaDB (worker3): unaffected — different node entirely.
  Flux, ingress, vault: all unaffected — no NFS dependency.
  CSI: 1 of 2 controllers degraded, but worker2 controller still healthy.

  Kernel dmesg on worker1:
  ```
  [43808.495309] nfs: server 10.0.40.120 not responding, timed out
  ```
  Continuous timeout messages every few seconds — soft mount working
  as designed, returning errors instead of hanging.

Cascade:
  eth1 down → NFS unreachable from worker1 → soft mount returns I/O
  errors → Grafana can't restart (volume stat fails) → WordPress
  readiness probe doesn't detect it (checks local file) → broken pod
  stays in endpoints → ~33% of user requests fail

What this tells me:
  The readiness probe was wrong. It checked a local file, so it never
  detected NFS failure. Traffic kept flowing to a pod that couldn't
  serve requests. This is the exact scenario readiness probes exist
  for — and it wasn't configured to catch it.

_____________________________________________________________________

[Fixes Applied]

Fix 1 — WordPress readiness probe (checks NFS now):
  ```yaml
  # Before: checked local file — didn't detect NFS failure
  readinessProbe:
    httpGet:
      path: /wp-includes/images/blank.gif

  # After: checks NFS-mounted path — detects storage failure
  readinessProbe:
    httpGet:
      path: /wp-content/index.php
    timeoutSeconds: 5

  # Liveness stays on local file — restarting won't fix NFS
  livenessProbe:
    httpGet:
      path: /wp-includes/images/blank.gif
  ```

Fix 2 — Grafana HA (3 replicas + anti-affinity):
  ```yaml
  grafana:
    replicas: 3
    affinity:
      podAntiAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app.kubernetes.io/name: grafana
            topologyKey: kubernetes.io/hostname
    persistence:
      accessModes:
        - ReadWriteMany
  ```

_____________________________________________________________________

[Test 1.2 — Validate fixes (same test, eth1 down again)]

Action:
  Same interface down on worker1. Observed behavior with fixes applied.

What happened:
  WordPress worker1 pod went 1/2 Running (readiness now fails on NFS
  path). Removed from endpoints immediately. Only worker2 + worker3
  in endpoints.

  ```
  wordpress   10.244.207.88:80,10.244.29.139:80   ← only healthy pods
  ```

  20 curl requests: all HTTP 200, 100% success rate.

  | Metric           | Before Fix                  | After Fix                 |
  |------------------|-----------------------------|---------------------------|
  | Worker1 pod      | 2/2 Ready (wrong)           | 1/2 Ready (correct)       |
  | Endpoints        | 3 pods (broken included)    | 2 pods (healthy only)     |
  | Traffic success  | ~90% (1/10 timeout)         | 100%                      |

  Grafana: 2 of 3 replicas still serving (anti-affinity across workers).
  No Grafana downtime.

_____________________________________________________________________

[Recovery]

  ```
  ip link set eth1 up
  ```
  NFS mounts recovered automatically (soft mount, no stale handles).
  WordPress worker1 pod went back to 2/2, re-added to endpoints.
  First 2 requests after restore hit a brief NFS reconnect window (~6s),
  then fully recovered. No manual intervention needed.

_____________________________________________________________________

[Findings]

1. Readiness probes must check the actual failure domain. A probe
   checking a container-local file can't detect NFS failure — the pod
   stays "Ready" while unable to serve. Changed readiness to check
   /wp-content/index.php (NFS-mounted), liveness stays on local file
   (restarting won't fix NFS on the same node).

2. Single-replica services are fully down on any node-local failure.
   Grafana with 1 replica on the affected worker = complete outage.
   Fixed with 3 replicas + anti-affinity. Same pattern already applied
   to vault-agent-injector (from app-pod-kill-wordpress-mariadb-injector.md race condition fix).

3. Soft mount works correctly for partial failures. Returns I/O errors
   fast (~9s), no stale mounts after recovery, no manual cleanup.
   Kernel dmesg shows continuous timeout messages during outage —
   expected behavior, not an issue.

4. CSI controller redundancy works. 1 of 2 controllers degraded on
   worker1, but worker2 controller handled all provisioning. No impact
   on new PVC creation during outage.

_____________________________________________________________________

[References]

- TS-K8S-003 — NFS hard mount pod hangs
- TS-K8S-015 — Stale NFS mount on CSI restart
- TS-K8S-018 — CSI controller network placement
- storage-full-nas-shutdown.md — full NAS outage (validates the probe fix at scale)
- kubernetes/dev/deployments/apps/wordpress/deployment.yaml — readiness probe config
- kubernetes/dev/deployments/apps/monitoring/helm-release.yaml — Grafana HA config
