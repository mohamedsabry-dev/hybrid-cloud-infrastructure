DR Test: Partial Master Loss (2 of 3)
Date: 2026-04-21
Result: PASS
_____________________________________________________________________

[Info]
Domain: Kubernetes / HA / etcd / DNS / Monitoring
Environment: DEV — 3 masters (1010/1011/1012) + 3 workers, v1.35.3
Triggered by: Pre-publish DR validation — what happens when the
  cluster loses majority of control plane nodes?

_____________________________________________________________________

[Planned Scope]

Force shutdown 2 of 3 master nodes from Proxmox. Observe etcd quorum
loss, API server behavior, worker pod survival, DNS resolution,
monitoring stack, and application availability.

_____________________________________________________________________

[Pre-State]

All 6 nodes Ready. Key placement: CoreDNS on master1 + master3,
vault-agent-injector on master1 + master3, WordPress (x2) on worker1,
MariaDB on worker2, Grafana on worker1, Prometheus on worker2,
Loki on worker3, ingress-nginx on worker2 + worker3.

_____________________________________________________________________

[Test 1.1 — Shutdown master2 + master3]

Action:
  ```
  qm stop 1011 --skiplock    # master2
  qm stop 1012 --skiplock    # master3
  ```
  Surviving master: master1 (10.0.61.10)

What happened:

  kubectl — DEAD. All commands hung indefinitely. API server on master1
  is running but etcd has no quorum (1/3). etcd requires majority to
  accept any reads or writes → API server has nothing to serve from.

  Worker pods — ALL STILL RUNNING. Verified via `crictl ps` on worker1
  (18 containers running). Kubelet runs from cached pod specs, doesn't
  need API server. No evictions occurred — controller-manager is frozen
  (can't reach etcd to make decisions).

  Pod networking (Calico) — FULLY FUNCTIONAL. Direct pod-to-pod
  communication works (WordPress → MariaDB by IP confirmed). CNI
  dataplane is already programmed on each node, doesn't need API server.

  CoreDNS — COMPLETELY DEAD. Both CoreDNS pods are running (master1 +
  master3), but master1's CoreDNS watches the API server for Endpoints
  updates. API server frozen → CoreDNS can't serve → all DNS queries
  timeout. This is the single biggest impact: every service using k8s
  DNS names breaks, even though all underlying pods are healthy.

  WordPress — DOWN. Pods running, MariaDB running, network works. But
  wp-config.php uses DB_HOST=mariadb.database.svc.cluster.local → DNS
  dead → can't resolve → "Error establishing a database connection."

  Grafana — UP BUT DEGRADING. This was unexpected. Datasource config
  uses service names (prometheus.monitoring.svc, loki.monitoring.svc).
  DNS is dead. But Prometheus dashboards partially worked because
  Grafana's Go HTTP client has an internal DNS cache — it was still
  using the cached IP from before shutdown. Loki datasource was dead
  (cache expired or never warmed for that FQDN format). Direct IP
  wget confirmed both backends were healthy — only DNS was missing.

  Monitoring degradation was progressive, not instant:
  - Dashboards using direct-scrape metrics (kubelet, cAdvisor): partially
    worked until Prometheus couldn't refresh service discovery targets
  - Dashboards using kube-state-metrics: failed immediately (queries
    API server)
  - Node Exporter dashboards: "No data" despite exporters running
    (label matching depends on API server metadata)

Cascade:
  2/3 masters down → etcd quorum lost → API server frozen → CoreDNS
  can't serve → all DNS-dependent apps break → WordPress down despite
  all app pods being healthy

What this tells me:
  CoreDNS is the hidden SPOF. It's not the pod failures that kill
  applications — it's the DNS dependency chain. Every k8s app uses
  service names by default. When DNS dies, the entire service mesh
  collapses even though all the underlying pods and networking work.

_____________________________________________________________________

[Recovery]

  Step 1 — Start master2:
  ```
  qm start 1011
  ```
  T+30s: etcd quorum restored (2/3), API server serving.
  T+60s: kubectl responds, CoreDNS resolves, WordPress reconnects to
  MariaDB, Grafana → Loki reconnects.

  Step 2 — CrashLoopBackOff pods recovered over ~5 minutes:

  calico-kube-controllers (master1): liveness probe queries API server →
  failed during outage → kubelet killed container 8 times. Key detail:
  this is the policy sync controller, NOT the dataplane (calico-node).
  Dataplane kept forwarding packets the entire time.

  flux kustomize-controller (worker1): health endpoints depend on API
  server → process crashed → CrashLoopBackOff with exponential backoff.

  Why ~5 minutes: pods in CrashLoopBackOff use exponential backoff
  (10s → 20s → 40s → 80s → 160s → 300s cap). After 27 minutes of
  outage, pods were at the 5-min cap. Each had to wait for its current
  timer to expire. Staggered recovery is expected — not slow, just
  backoff math. No manual intervention needed.

  Step 3 — Start master3:
  ```
  qm start 1012
  ```
  Full cluster restored. All 3 etcd members healthy, all pods Running.

_____________________________________________________________________

[etcd Logs — Quorum Loss Anatomy]

  Captured from Loki during the outage window (21:47–21:55 UTC):

  Phase 1 (21:49): Normal operation. Periodic snapshot at applied-index
  5430612, Raft request processing at ~111ms.

  Phase 2 (21:50:24): Master1 detects master3 dead. Both TCP streams
  (Message + MsgApp v2) died at the same millisecond — confirms force
  shutdown, not graceful leave. "unexpected EOF" on both streams.

  Phase 3 (21:50:25): Leader heartbeat degradation. Heartbeat expected
  within 200ms, took 295ms — leader wasting time on unreachable peers.

  Phase 4 (21:50:25): API server requests failing. ReadIndex requests
  timed out (500ms retries). Lease operations queued but uncommittable
  — Raft requires majority agreement.

  Phase 5 (21:54:36): gRPC flood — 275 ERROR entries in rapid
  succession. API server retrying etcd aggressively without backoff.
  This is the root cause of "kubectl hangs."

  Phase 6 (recovery): Master2 etcd synced ~357 missed Raft index
  entries (5430969 - 5430612). Quorum restored, API server immediately
  began serving.

_____________________________________________________________________

[Findings]

1. etcd quorum loss (1/3 surviving) = total control plane failure.
   API server cannot serve reads or writes. kubectl, CoreDNS, service
   discovery — all dead.

2. Worker pods survive indefinitely. Kubelet runs from cached state,
   Calico dataplane stays programmed, no evictions occur (controller-
   manager frozen). Running workloads are unaffected.

3. CoreDNS is the critical SPOF for applications. WordPress was down
   not because anything in its stack broke — pods running, network
   working, DB healthy. Only DNS resolution was missing. Every app
   using k8s service names breaks during quorum loss.

4. Grafana's partial survival was accidental (Go DNS cache), not
   designed. Not something to rely on. Loki datasource died when
   cache expired.

5. Monitoring degrades progressively. Direct-scrape metrics (kubelet,
   cAdvisor) partially survive. kube-state-metrics dashboards fail
   immediately. Prometheus keeps scraping cached targets but can't
   refresh service discovery.

6. CrashLoopBackOff recovery takes ~5 minutes after quorum restore.
   Exponential backoff (capped at 300s) means pods recover at staggered
   intervals. This is expected — don't panic and force-delete pods.

7. calico-kube-controllers crash-loops ≠ network outage. The controller
   handles policy sync (control plane). calico-node DaemonSet handles
   packet forwarding (dataplane). They are separate — dataplane works
   while controller is down.

_____________________________________________________________________

[Concerns / Future Work]

1. DNS resilience: consider NodeLocal DNSCache (DaemonSet, caches DNS
   on link-local 169.254.20.10) so cached service names survive short
   control plane outages. Alternatively, IP-based connections for
   critical paths (WordPress → MariaDB).

2. Wave 2 planned: vault agent sidecar behavior during quorum loss
   (token TTL expiry), Flux reconciliation after long outage, Calico
   policy sync lag during recovery, Prometheus TSDB gap behavior,
   longer outage duration (30+ min, node lease expiry).

_____________________________________________________________________

[References]

- network-ipa-dns-outage.md — DNS SPOF via different cause (IPA down)
- etcd-single-node-recovery.md — single etcd node recovery
- CoreDNS ClusterIP: 10.96.0.10
- Proxmox VMIDs: 1010 (master1), 1011 (master2), 1012 (master3)
