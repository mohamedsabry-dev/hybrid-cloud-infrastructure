DR Test: Full NAS Shutdown — Storage Class Behavior Under Outage
Date: 2026-04-17
Result: PASS — storage class design validated
_____________________________________________________________________

[Info]
Domain: NFS / Kubernetes / Storage Classes / Pod Resilience
Environment: DEV — 3 workers (eth1 10.0.40.x storage interface),
  NAS at 10.0.40.120, 6 NFS-dependent apps
Triggered by: Need to understand how different storage classes behave
  when the NAS goes completely offline — soft mount vs hard mount,
  read-heavy vs write-heavy workloads

_____________________________________________________________________

[Planned Scope]

Power off NAS entirely. Observe behavior across all NFS-dependent apps,
escalating from short outage (~2 min) to extended (10+ min). Compare
soft mount (fast-fail) vs hard mount (hang-until-recovery).

Storage class design:
  | StorageClass  | Mount  | Timeout       | Used By                          |
  |---------------|--------|---------------|----------------------------------|
  | nfs-retain    | soft   | 3s × 3 = ~9s | WordPress, Grafana, Prometheus,  |
  |               |        |               | Loki, Alertmanager               |
  | nfs-database  | hard   | 60s × 5 = 5m | MariaDB                          |

Pre-test fix applied: restricted csi-nfs-node DaemonSet to worker nodes
only (masters have no storage interface). DESIRED went from 6 → 3.
See kubernetes/dev/deployments/infrastructure/storage/ for the change.

_____________________________________________________________________

[Pre-State]

All 6 nodes Ready. NAS online, all PVCs Bound.
  WordPress: 3 pods (worker1/2/3), soft mount
  MariaDB: 1 pod (worker2), hard mount
  Grafana: 3 pods (worker1/2/3), soft mount
  Prometheus: 1 pod (worker3), soft mount
  Loki: 1 pod (worker2), soft mount
  Alertmanager: 1 pod (worker1), soft mount

Non-NFS components (ingress, vault, flux, CoreDNS, etcd): no storage
dependency, expected to survive all tests.

_____________________________________________________________________

[Test 1.1 — Short NAS Restart (~2 min outage)]

Action:
  NAS restart via Synology UI. Down ~2-2.5 minutes.

What happened:
  WordPress (soft): endpoints removed within seconds. All 3 pods went
  1/2 Running (readiness failed, liveness passed). Zero restarts. When
  NAS recovered, endpoints restored immediately — no restart needed.

  ```
  wordpress   10.244.207.68:80,10.244.29.174:80,10.244.62.8:80   # 3 endpoints
  wordpress   10.244.29.174:80,10.244.62.8:80                    # 2 (removing)
  wordpress   10.244.62.8:80                                     # 1
  wordpress   10.244.207.68:80,10.244.29.174:80,10.244.62.8:80   # 3 (restored)
  ```

  MariaDB (hard): hung silently. I/O operations in D state (uninterruptible
  sleep). No errors returned to application — just paused. Resumed
  automatically when NFS recovered. Zero restarts.

  Prometheus (soft): only component that restarted (+1). TSDB writes to
  WAL failed → Prometheus detected write corruption risk → crashed.
  Kubelet restarted after NFS recovered, Prometheus replayed WAL and
  resumed in ~30s.

  Grafana, Loki, Alertmanager (soft): all survived. Not actively writing
  during the 2-minute window.

  MariaDB logs showed an unexpected cascade:
  ```
  22:04:43 [Warning] Aborted connection 4313 to db: 'unconnected'
    user: 'unauthenticated' host: '10.0.64.11' (closed without auth)
  ```
  WordPress on soft mount couldn't read wp-config.php from NFS → couldn't
  get DB credentials → connected to MariaDB but closed before auth.
  MariaDB was fine — the clients were the ones failing.

What this tells me:
  Soft mount returns errors fast (~9s) — apps that handle I/O errors
  gracefully survive, apps with continuous writes crash. Hard mount just
  pauses everything — correct for databases where data integrity matters
  more than availability. A 2-minute outage is within both timeouts.

_____________________________________________________________________

[Test 1.2 — Second NAS Restart with Video Streaming]

Why this test: first test proved short outage behavior with idle apps.
  What about active READ operations?

Action:
  Same NAS restart (~2 min). User actively watching/downloading videos
  from WordPress during outage.

What happened:
  WordPress: still zero restarts. Video playback paused/errored but PHP
  didn't crash — READ failures return error to client, process continues.
  Prometheus: restarted again (+1, now at 10).
  MariaDB: survived again (hard mount pause/resume).

What this tells me:
  READ failures on soft mount are graceful. PHP catches the I/O error,
  returns HTTP 500/503 to the browser, and moves on. No state corruption,
  no process death. This is fundamentally different from WRITE failures.

_____________________________________________________________________

[Test 1.3 — Third NAS Restart with 90MB Upload (WRITE test)]

Why this test: reads survive. Do writes?

Action:
  4 × 90MB files queued for upload. NAS restarted mid-upload.

What happened:
  WordPress: STILL zero restarts. Upload failed but container survived.

  Upload results:
  | File   | State When NAS Died     | Result              |
  |--------|-------------------------|---------------------|
  | File 1 | Completed before outage | Found in library    |
  | File 2 | Mid-upload              | Lost — not on NFS   |
  | File 3 | Queued (not started)    | Lost — browser only |
  | File 4 | Queued (not started)    | Lost — browser only |

  Apache logged the I/O errors:
  ```
  [core:error] (5)Input/output error: AH00036: access to
    /wp-content/index.php failed (filesystem path '/var/www/html/wp-content')
  ```
  Readiness probe got 403 (I/O error on NFS path) → endpoints removed.
  Liveness probe got 200 (checks /wp-includes/images/blank.gif — local
  filesystem, not NFS) → container stayed alive.

What this tells me:
  WordPress WRITE failures are also graceful. Each upload is a one-shot
  request — failure returns error to client, PHP moves on. No persistent
  write stream to corrupt. Data is lost (File 2) but the process survives.

  This is the key difference from Prometheus: WordPress writes are
  request-scoped (upload then done), Prometheus writes are continuous
  (WAL every 15s). Continuous write failure = corruption = crash.
  One-shot write failure = error response = survive.

_____________________________________________________________________

[Test 1.4 — Extended NAS Outage (10+ min)]

Why this test: soft mount timeout is ~9s, hard mount is ~5 min.
  What happens beyond both thresholds?

Action:
  NAS shutdown, left down for 10+ minutes. 4 uploads in progress.

What happened:
  WordPress (soft): 1/2 Running, STILL zero restarts after 10+ min.
  Liveness checks container filesystem → always passes. Readiness
  checks NFS path → always fails. Pod alive but isolated.

  Live exec into the pod confirmed the split:
  - /var/www/html/wp-includes/ (overlay FS) → ls returned instantly
  - /var/www/html/wp-content/ (NFS mount) → cd hung, needed Ctrl+C

  MariaDB (hard): 2/2 Running after 10 min. Hard mount with `intr` means
  I/O hangs but process stays alive. TCP liveness probe passes (MariaDB
  socket responds, doesn't need disk). At 10 min we're past the 5-min
  hard timeout — but `intr` allows the kernel to interrupt the wait.

  Grafana (soft): CrashLoopBackOff at 25+ restarts. Grafana's liveness
  probe requires NFS access for dashboard reads → fails → container
  restarts → NFS still down → CreateContainerError → loop.

  Prometheus (soft): restart count at 11. Same TSDB write failure pattern.

What this tells me:
  Extended outage separates apps by their liveness probe design:
  - WordPress: liveness on local FS → survives indefinitely
  - Grafana: liveness needs NFS → CrashLoopBackOff
  - Prometheus: continuous writes → crashes regardless of probes
  - MariaDB: hard mount + TCP liveness → frozen but alive

  The volume mount architecture makes this work:
  /var/www/html/ is container image (overlay FS). Only /wp-content/ is
  NFS. Liveness checks /wp-includes/images/blank.gif (overlay) → passes.
  Readiness checks /wp-content/index.php (NFS) → fails. This separation
  is the entire reason WordPress survives without restart.

_____________________________________________________________________

[Recovery]

  NAS powered back on. All apps auto-recovered:
  - WordPress: endpoints restored in seconds, 2/2 Running, zero restarts
  - MariaDB: I/O resumed from D state, zero data loss
  - Grafana: CrashLoopBackOff resolved, containers started normally
  - Prometheus: restarted clean, replayed WAL
  - Loki, Alertmanager: back to healthy

  No manual intervention required for any component.

_____________________________________________________________________

[Findings]

1. Soft mount is fail-fast, but impact depends on workload pattern.
   Read-heavy apps (WordPress, Grafana idle) survive — I/O error returned
   to caller, process continues. Write-heavy apps (Prometheus TSDB) crash
   because continuous write failure = corruption risk = exit.

2. Hard mount is correct for databases. MariaDB I/O hangs transparently,
   resumes when NFS returns. No errors, no corruption, no restart. Outage
   must stay under 5 min (timeo=600 × retrans=5) or `intr` must be set.

3. Liveness vs readiness probe separation is the key design. WordPress
   survives indefinitely because liveness checks container FS (always OK)
   while readiness checks NFS path (fails → isolation). If liveness also
   checked NFS, pods would CrashLoopBackOff like Grafana — restarting
   won't fix NFS, it just adds restart delay.

4. WordPress upload data loss is graceful but real. Mid-upload file is
   lost (PHP temp cleaned, NFS write never completed). Completed uploads
   survive. Browser queue is lost on page error. But the process itself
   never crashes — each upload is independent, failure returns error.

5. Grafana needs liveness probe redesign for NFS resilience. Current
   probe requires NFS access → CrashLoopBackOff during extended outage.
   Same pattern as WordPress (local FS check) would let it survive.

6. MariaDB "aborted connection" logs during outage are misleading —
   MariaDB is fine, it's WordPress clients failing. WordPress can't read
   wp-config.php (soft mount error) → connects without credentials →
   closes connection → MariaDB logs "closed without auth."

_____________________________________________________________________

[References]

- troubleshooting/kubernetes/36-wordpress-liveness-probe-nfs-resilience.md (TS-K8S-036)
- kubernetes/dev/deployments/infrastructure/storage/storageclass.yaml
- storage-single-worker-nfs-down.md — single worker NFS failure
- app-ingress-nginx-failover.md — ingress layer tests
