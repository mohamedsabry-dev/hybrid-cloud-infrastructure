# Partial Master Loss (2 of 3)
# Date: 2026-04-21
# Result: TESTED — PASSED (behavior matched expectations + new findings)

_____________________________________________________________________

[Info]
Author: Sabry
Domain: Kubernetes / HA / etcd / DNS / Monitoring
Sub-techs: etcd quorum, kube-apiserver, CoreDNS dependency chain,
           Calico CNI, kubelet cached state, Prometheus service discovery,
           Grafana datasource caching, Vault agent sidecar
Environment: DEV k8s-dev cluster | Proxmox
Cluster: 3 masters (1010, 1011, 1012) + 3 workers (1020, 1021, 1022)
K8s version: v1.35.3
Triggered by: Pre-publish DR validation

_____________________________________________________________________

[Scope]

Force shutdown 2 of 3 master nodes. Test etcd quorum loss, API server
behavior, worker pod survival, DNS resolution, monitoring stack behavior,
and application availability.

_____________________________________________________________________

[Pre-State]

All 6 nodes Ready. Full workload running:

```
$ kubectl get nodes
NAME                    STATUS   ROLES           AGE   VERSION
k8s-master1.lab.local   Ready    control-plane   25d   v1.35.3
k8s-master2.lab.local   Ready    control-plane   25d   v1.35.3
k8s-master3.lab.local   Ready    control-plane   25d   v1.35.3
k8s-worker1.lab.local   Ready    <none>          25d   v1.35.3
k8s-worker2.lab.local   Ready    <none>          25d   v1.35.3
k8s-worker3.lab.local   Ready    <none>          25d   v1.35.3
```

Workload distribution before shutdown:
- master1: calico-kube-controllers, coredns, etcd, apiserver, controller-manager,
           scheduler, kube-proxy, alertmanager, node-exporter, promtail, vault-agent-injector
- master2: coredns, etcd, apiserver, controller-manager, scheduler, kube-proxy,
           node-exporter, promtail, etcd-backup cronjobs
- master3: etcd, apiserver, controller-manager, scheduler, kube-proxy,
           calico-node, node-exporter, promtail, remediation, vault-agent-injector
- worker1: wordpress (x2), flux controllers (x4), grafana, calico-node,
           csi-nfs-node, kube-proxy, node-exporter, promtail, loki-canary
- worker2: mariadb-0, ingress-nginx, csi-nfs-controller, csi-nfs-node,
           calico-node, kube-proxy, metrics-server, node-exporter, promtail,
           loki-canary, prometheus-0
- worker3: ingress-nginx (x2), csi-nfs-controller, csi-nfs-node, calico-node,
           kube-proxy, metrics-server, kube-state-metrics, prometheus-operator,
           node-exporter, promtail, loki-canary, loki-0

_____________________________________________________________________

[Execution]

# Step 1 — Force shutdown master2 and master3

From Proxmox shell:
```bash
qm stop 1011 --skiplock    # k8s-master2 (10.0.61.11)
qm stop 1012 --skiplock    # k8s-master3 (10.0.61.12)
```

Surviving master: k8s-master1 (VMID 1010, IP 10.0.61.10)

_____________________________________________________________________

[Observations]

# 1. kubectl — DEAD

All kubectl commands from workstation failed immediately. No response,
no timeout message — just hung indefinitely.

```
$ kubectl get nodes     → no response
$ kubectl get pods -A   → no response
```

Reason: kubectl connects to the API server. The API server on master1 is
running but cannot serve requests because etcd has no quorum (1 of 3 members).
etcd requires majority (2 of 3) to accept reads or writes. With only 1 member
reachable, etcd refuses all operations, and the API server has nothing to
serve from.

# 2. Worker pods — ALL STILL RUNNING

Verified via crictl on worker1 (SSH from Proxmox):

```
[root@k8s-worker1 ~]# crictl ps | wc -l
19
```

All 18 containers running (header line + 18 containers). Full output:
```
CONTAINER           STATE     NAME                     POD
3b95ddec2d881       Running   manager                  notification-controller-7f5d7cb966-vchct    flux-system
b4f121ab0ed7f       Running   manager                  source-controller-6d8d58659f-r28nh          flux-system
fab91b771df38       Running   manager                  helm-controller-844f6958dc-4f4dx             flux-system
4bb79e85f5b51       Running   vault-agent              kube-prometheus-stack-grafana-...            monitoring
fe311313f0315       Running   grafana                  kube-prometheus-stack-grafana-...            monitoring
c6f9b0503ecb1       Running   vault-agent              wordpress-6d4f6bbd46-mmq2q                  apps
ecc94fa80df35       Running   vault-agent              wordpress-6d4f6bbd46-ghspb                  apps
3ac65b2d36657       Running   wordpress                wordpress-6d4f6bbd46-ghspb                  apps
c0a6863a17007       Running   wordpress                wordpress-6d4f6bbd46-mmq2q                  apps
dada8e7de6dad       Running   grafana-sc-dashboard     kube-prometheus-stack-grafana-...            monitoring
5e39d679e23dc       Running   promtail                 promtail-54nsf                               monitoring
fddeff7412959       Running   loki-canary              loki-canary-fdm8f                            monitoring
de6923482ed8b       Running   calico-node              calico-node-756lw                            kube-system
bb49a7c5fbd38       Running   nfs                      csi-nfs-node-s825d                           kube-system
5a255a4ca66bf       Running   node-driver-registrar    csi-nfs-node-s825d                           kube-system
cc1193e2ab2b0       Running   liveness-probe           csi-nfs-node-s825d                           kube-system
7d654cb88009a       Running   kube-proxy               kube-proxy-pmm4p                             kube-system
109e7e7931e6d       Running   node-exporter            ...prometheus-node-exporter-kk2ml            monitoring
```

Kubelet operates independently — it has its pod specs cached locally and
continues running containers without needing the API server.

No evictions occurred. Evictions require the kube-controller-manager to
communicate through the API server + etcd. With etcd quorum lost, the
controller-manager is frozen — it cannot make eviction decisions.

# 3. Pod networking (Calico CNI) — FULLY FUNCTIONAL

Tested from inside WordPress container on worker1:

```
root@wordpress-6d4f6bbd46-ghspb:/var/www/html# curl -s --connect-timeout 3 http://10.244.207.102:3306 2>&1
(connected — silent output, MariaDB speaks binary not HTTP)

root@wordpress-6d4f6bbd46-ghspb:/var/www/html# curl -s --connect-timeout 3 http://10.244.62.55:3000 2>&1
<a href="/login">Found</a>.
```

Direct pod-to-pod communication via Calico works perfectly. The CNI
dataplane (iptables/IPVS rules, BGP routes) is already programmed on
each node and does not need the API server to forward packets.

# 4. CoreDNS — COMPLETELY DEAD

```
root@wordpress-6d4f6bbd46-ghspb:/var/www/html# curl -s --connect-timeout 3 http://mariadb.database.svc.cluster.local:3306 2>&1
(empty — DNS resolution failed, connection never attempted)

root@wordpress-6d4f6bbd46-ghspb:/var/www/html# curl -s --connect-timeout 3 http://kube-prometheus-stack-grafana.monitoring.svc.cluster.local 2>&1
(empty — DNS resolution failed)

root@wordpress-6d4f6bbd46-ghspb:/var/www/html# php -r "var_dump(gethostbyname('mariadb.database.svc.cluster.local'));"
^C  (hung indefinitely — PHP blocks waiting for DNS)
```

From Grafana container on worker1:
```
$ wget -q -O /dev/null --timeout=3 http://prometheus-kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090/-/healthy
wget: bad address 'prometheus-kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090'

$ wget -q -O /dev/null --timeout=3 http://loki.monitoring.svc.cluster.local:3100/ready
wget: bad address 'loki.monitoring.svc.cluster.local:3100'

$ nslookup prometheus-kube-prometheus-stack-prometheus.monitoring.svc.cluster.local
;; connection timed out; no servers could be reached

$ cat /etc/resolv.conf
search monitoring.svc.cluster.local svc.cluster.local cluster.local lab.local
nameserver 10.96.0.10
options ndots:5
```

CoreDNS pods were on master1 and master3. Master3 is down. Master1's CoreDNS
pod is running but it watches the API server for Endpoints/Services updates.
The API server is frozen (etcd quorum lost), so CoreDNS cannot serve — all
DNS queries time out.

This is the single biggest impact of quorum loss: every service that uses
Kubernetes DNS names for connectivity breaks, even though all underlying
pods are healthy and reachable by IP.

# 5. WordPress — DOWN (DNS dependency)

WordPress pods are running on worker1. MariaDB is running on worker2.
Network between them works (proven by direct IP curl).

But WordPress connects to MariaDB via service name in wp-config.php:
DB_HOST=mariadb.database.svc.cluster.local

DNS is dead → WordPress cannot resolve MariaDB hostname → database
connection fails → web page does not load.

The ingress-nginx controllers on workers are still running, so the
HTTP path from browser to WordPress pod works — WordPress itself
returns the error (cannot connect to database).

# 6. Grafana — UP BUT DEGRADING (the unexpected one)

Grafana UI was fully accessible via browser. This was initially surprising
since its datasource config uses service names:

```yaml
# Grafana datasource provisioning config:
- name: "Prometheus"
  url: http://kube-prometheus-stack-prometheus.monitoring:9090/
  access: proxy

- name: "Loki"
  url: http://loki.monitoring.svc.cluster.local:3100
  access: proxy

- name: "Alertmanager"
  url: http://alertmanager.monitoring.svc:9093
  access: proxy
```

All three datasources use service names, yet Prometheus dashboards partially
worked while Loki was completely dead.

Explanation — the dependency chain:

  Browser → Ingress (worker, running) → Grafana pod (worker1, running)
  Grafana → Prometheus (service name needs DNS)
  Grafana → Loki (service name needs DNS)

Grafana uses access: proxy mode — its Go backend makes HTTP calls to
datasources. Go's HTTP client has an internal DNS cache. The DNS resolution
for Prometheus was cached from before the masters went down. Grafana
continued querying Prometheus using the cached IP address.

Loki's DNS cache likely expired or was never warmed for the specific FQDN
format used, so all Loki queries failed.

Direct IP verification from Grafana container:
```
$ wget http://10.244.207.107:9090/-/healthy    → success (Prometheus alive)
$ wget http://10.244.29.138:3100/ready         → success (Loki alive)
```

Both backends are healthy — the only failure point is DNS resolution.

# 7. Grafana dashboard behavior — mixed results explained

API Server dashboard:
  - Showed live data until ~19:45, then stopped
  - Reason: Prometheus scraped kube-apiserver metrics directly by IP.
    Masters 2+3 went down → scrape targets gone → data stopped for those
    instances. Master1's apiserver is running but unresponsive (etcd).

Kubelet dashboard:
  - Summary panels (Running Kubelets, Running Pods, etc.): "No data"
  - Operation Rate panel: showed data for 10.0.61.10 (master1) only
  - Reason: summary panels use kube-state-metrics which queries the API
    server (dead). Operation Rate scrapes kubelet /metrics directly by
    IP — only master1's kubelet is reachable.

Node Exporter dashboard:
  - All panels: "No data"
  - Reason: node exporter pods are running on all nodes and exporting
    metrics. But the dashboard uses label queries that depend on
    kube-state-metrics or API server metadata for label matching.
    Without API server context, Prometheus cannot label-match the
    node exporter targets.

Pod Resources / WordPress dashboard:
  - Showed data until ~19:50, then went flat
  - Reason: cAdvisor metrics scraped from kubelet by IP. Data stopped
    when Prometheus could not refresh its service discovery targets
    from the API server. Prometheus keeps scraping targets it already
    knows (cached), but cannot discover new ones or refresh labels.

# 8. Loki — DEAD (no logs queryable)

Grafana could not query any logs from Loki, even though Loki pod on
worker3 and Promtail pods on all nodes were running and shipping logs.

Reason: Grafana → Loki datasource uses service name DNS. DNS is dead.
Loki itself is healthy (verified by direct IP wget) but Grafana cannot
reach it.

_____________________________________________________________________

[etcd Logs Analysis — Quorum Loss and Recovery]

Logs captured from Grafana/Loki during the outage window (21:47–21:55 UTC).
Three etcd member IDs involved:
  4c17d04fdb863468 = master1 (survivor)
  2699402e05a84d4b = master2 (shutdown, then recovered)
  e0a1c396a5ca70ba = master3 (shutdown)

# Phase 1 — Normal operation (21:48–21:49)

etcd on master2 running normally. Periodic snapshot triggered at
applied-index 5430612. Raft request processing at ~111ms. Healthy.

```
21:49:04  INFO  "triggering snapshot"
  local-member-id: "2699402e05a84d4b"
  local-member-applied-index: 5430612
  local-member-snapshot-count: 10000
  snapshot-forced: false

21:48:22  INFO  "trace[988869650] transaction"
  detail: "{read_only:false; response_revision:4322394; number_of_response:1}"
  duration: "111.143906ms"
```

# Phase 2 — Quorum loss detected (21:50:24)

Master1 detects master3 is dead. TCP connections severed mid-stream.
Force VM shutdown caused abrupt connection termination (unexpected EOF),
not a graceful Raft member leave.

```
21:50:24  WARN  "peer became inactive (message send to peer failed)"
  peer-id: "e0a1c396a5ca70ba"
  error: "failed to read e0a1c396a5ca70ba on stream MsgApp v2 (unexpected EOF)"

21:50:24  WARN  "lost TCP streaming connection with remote peer"
  stream-reader-type: "stream Message"
  local-member-id: "4c17d04fdb863468"
  remote-peer-id: "e0a1c396a5ca70ba"
  error: "unexpected EOF"

21:50:24  WARN  "lost TCP streaming connection with remote peer"
  stream-reader-type: "stream MsgApp v2"
  local-member-id: "4c17d04fdb863468"
  remote-peer-id: "e0a1c396a5ca70ba"
  error: "unexpected EOF"
```

Both the Message stream (heartbeats/elections) and MsgApp v2 stream
(log replication) died at the same millisecond — confirms force shutdown.

# Phase 3 — Leader degradation (21:50:24–21:50:25)

The surviving leader (master1) started failing heartbeats because it was
still trying to replicate to dead peers. Timeout/retry overhead caused
heartbeat delivery to exceed the expected interval.

```
21:50:25  WARN  "leader failed to send out heartbeat on time"
  to: "e0a1c396a5ca70ba"
  heartbeat-interval: "100ms"
  expected-duration: "200ms"
  exceeded-duration: "295.53012ms"
```

Heartbeat expected within 200ms, took 295ms. This is not a performance
problem — it is the leader wasting time on unreachable peers before giving up.

# Phase 4 — API server requests failing (21:50:25)

etcd could not serve consistent reads without quorum. ReadIndex requests
(the mechanism etcd uses to confirm read consistency) timed out and retried
indefinitely.

```
21:50:25  WARN  "waiting for ReadIndex response took too long, retrying"
  retry-timeout: "500ms"
```

Lease operations (node heartbeats, leader elections) queued up but could
not be committed to the Raft log.

```
21:50:25  WARN  "apply request took too long"
  took: "810.755206ms"
  expected-duration: "100ms"
  request: "lease_revoke:<id:4d4b9db123994b4f>"
```

The lease_revoke is etcd trying to clean up leases for the dead nodes.
It cannot commit this operation because Raft requires majority agreement.
The request sits in the log at 810ms (8x the expected 100ms), uncommittable.

# Phase 5 — gRPC flood (21:54:36)

275 ERROR-level gRPC entries in rapid succession:

```
21:54:36  ERROR  grpc: Server.processUnaryRPC failed to write status:
  connection error: desc = "transport is closing"
```

This is the API server (and other Kubernetes components) continuously
retrying gRPC calls to etcd. Every call fails because etcd cannot serve.
The API server does not back off — it retries aggressively, generating
a flood of errors. This is the root cause of "kubectl hangs" — the API
server is stuck in a retry loop against a quorum-less etcd.

# Phase 6 — Recovery (21:49-21:50 on master2 logs)

After qm start 1011, master2's etcd rejoined the cluster and caught up:

```
21:50:16  INFO  "saved snapshot to disk"
  snapshot-index: 5430969

21:50:16  INFO  "triggering snapshot"
  local-member-id: "4c17d04fdb863468"
  local-member-applied-index: 5430969
```

Master2 synced the ~357 Raft index entries it missed during downtime
(5430969 - 5430612). Old snapshot files purged from disk (normal
housekeeping). Quorum restored, API server immediately began serving.

_____________________________________________________________________

[Key Findings]

1. etcd quorum loss (1 of 3) makes the entire control plane non-functional.
   API server cannot serve reads or writes.

2. Worker pods survive indefinitely. Kubelet runs from cached state.
   No evictions occur because the controller-manager is frozen.

3. Pod-to-pod networking (Calico CNI) works perfectly without the API
   server. The dataplane is already programmed.

4. CoreDNS is the critical single point of failure for applications.
   Even when app pods and their database pods are all healthy on workers,
   DNS-dependent connections break completely.

5. Monitoring degrades progressively, not instantly. Prometheus continues
   scraping cached targets and serving cached data. Dashboards that use
   direct-scrape metrics (kubelet, cAdvisor) partially work. Dashboards
   that depend on kube-state-metrics or API server label context fail
   immediately.

6. Grafana's Go HTTP client DNS cache is what kept Prometheus dashboards
   partially alive — a lucky implementation detail, not a design guarantee.

7. Pods with API-server-dependent liveness probes crash-loop during quorum
   loss, even on surviving nodes. Recovery is not instant — Kubernetes
   exponential backoff (up to 5 min cap) means pods recover at staggered
   intervals after quorum is restored. No manual intervention needed, but
   the delay is important to understand so operators don't panic and start
   force-deleting pods.

_____________________________________________________________________

[Concerns Raised During Test]

1. DNS is a hidden SPOF for applications

   WordPress was down not because anything was broken in its stack — both
   WordPress pods and MariaDB were running, network between them worked.
   The only missing piece was DNS resolution. This means any application
   using Kubernetes service names (which is all of them by default) will
   break during quorum loss.

   Potential mitigations considered:
   - NodeLocal DNSCache (DaemonSet on every node, caches DNS locally)
   - Raise CoreDNS cache TTL from default 30s to 300s+
   - Use direct IP / headless service for critical app → database paths
   - Place CoreDNS replicas on workers (partial — still needs API server
     for endpoint updates, but cache would survive longer)

   Decision: consider IP-based connections for critical paths
   (WordPress → MariaDB) to remove DNS dependency. NodeLocal DNSCache
   is the Kubernetes-native solution for broader DNS resilience.

2. Grafana datasource resilience is accidental

   Grafana's partial survival depended on Go's DNS cache — not on any
   deliberate design. If the Go runtime flushed its cache, Grafana →
   Prometheus would also break. This is not something to rely on.

3. NodeLocal DNSCache as future mitigation

   Deploying NodeLocal DNSCache (DaemonSet on every node, caches DNS on
   link-local 169.254.20.10) would let cached service names survive short
   control plane outages. Requires kubelet --cluster-dns reconfiguration
   across all nodes. Not addressing now — planned as a post-publish
   infrastructure improvement.

_____________________________________________________________________

[Wave 2 — Planned]

This test covered the immediate impact of quorum loss. A second wave is
planned to dig deeper into the API server dependency chain:

- Which pods survive indefinitely vs crash-loop, and why (probe config)
- Vault agent sidecar behavior — do injected secrets survive, do renewals
  fail, do pods lose credentials after token TTL expires
- Flux reconciliation — what happens when Flux controllers reconnect after
  a long outage (does it force-sync everything, does it diff correctly)
- Calico network policy enforcement — does policy sync lag cause temporary
  allow-all or deny-all windows during recovery
- Prometheus TSDB gap behavior — how does Prometheus handle the scrape gap
  when service discovery comes back (does it backfill, leave a gap, or
  double-count)
- Test with NodeLocal DNSCache deployed — does WordPress survive quorum loss
- Longer outage duration (30+ minutes) — do kubelet node leases expire,
  does the surviving master mark nodes as NotReady even without quorum

_____________________________________________________________________

[Recovery]

# Step 1 — Start master2

```bash
qm start 1011    # k8s-master2
```

Within ~30 seconds: etcd quorum restored (2 of 3 members), API server
begins serving requests.

Within ~60 seconds: kubectl responds, nodes visible, pods reporting status.

# Step 2 — CrashLoopBackOff pods during recovery

After master2 came back, several pods on worker and master nodes were in
CrashLoopBackOff. They resolved one by one over ~5 minutes without
manual intervention.

Affected pods and why:

  calico-kube-controllers (master1 — was running the entire time):
    - Liveness probe queries API server: https://10.96.0.1:443/apis/crd.projectcalico.org/v1/...
    - During quorum loss, API server returned HTTP 500 or timed out
    - Kubelet saw liveness probe fail → killed the container → restarted
    - This happened 8 times during the ~27 minute outage
    - Key detail: calico-kube-controllers handles policy sync (control plane).
      calico-node DaemonSet handles packet forwarding (dataplane). They are
      separate. Dataplane kept working even while the controller crash-looped.

  ```
  Warning  Unhealthy  26m (x6 over 27m)  kubelet  Readiness probe failed: Error verifying datastore:
      Get "https://10.96.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default":
      context deadline exceeded
  Warning  Unhealthy  26m (x6 over 27m)  kubelet  Liveness probe failed: Error verifying datastore:
      Get "https://10.96.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default":
      context deadline exceeded; Error reaching apiserver: ... http status code: 500
  Normal   Killing    17m (x4 over 26m)  kubelet  Container calico-kube-controllers failed liveness
      probe, will be restarted
  Normal   Pulled     12m (x8 over 154m) kubelet  Container image already present on machine
  Normal   Created    12m (x8 over 153m) kubelet  Container created
  Normal   Started    12m (x8 over 153m) kubelet  Container started
  ```

  flux kustomize-controller (worker1):
    - Health endpoints (/healthz, /readyz) depend on API server connectivity
    - Process itself crashed when API server was unreachable → connection refused
    - Kubelet killed via liveness probe → CrashLoopBackOff with exponential backoff

  ```
  Warning  Unhealthy  25m (x2 over 27m)   kubelet  Liveness probe failed:
      Get "http://10.244.62.50:9440/healthz": dial tcp 10.244.62.50:9440: connect: connection refused
  Warning  BackOff    21m (x13 over 27m)  kubelet  Back-off restarting failed container manager
  Warning  Unhealthy  21m (x13 over 153m) kubelet  Readiness probe failed:
      Get "http://10.244.62.50:9440/readyz": dial tcp 10.244.62.50:9440: connect: connection refused
  ```

# Why recovery took ~5 minutes (not instant)

Pods in CrashLoopBackOff use exponential backoff: 10s → 20s → 40s → 80s →
160s → 300s (capped at 5 minutes). A pod that had been crash-looping for
27 minutes was waiting at the 5-minute backoff cap. After quorum restored,
each pod had to wait for its current backoff timer to expire before retrying.

Pods recovered at staggered intervals because each was at a different point
in its backoff cycle. This is not slow recovery — it is the expected
Kubernetes backoff behavior. No manual intervention was needed.

# Step 3 — Start master3

```bash
qm start 1012    # k8s-master3
```

Full cluster restored. All 3 etcd members healthy. All pods Running.

# Recovery timeline

  T+0:00  qm start 1011
  T+0:30  etcd quorum restored, API server serving
  T+1:00  kubectl responds, nodes visible
  T+1:00  CoreDNS starts resolving again
  T+1:00  WordPress reconnects to MariaDB (DNS works)
  T+1:00  Grafana → Loki reconnects (DNS works)
  T+2:00  First CrashLoopBackOff pods recover
  T+5:00  All pods stabilized, full cluster health
  T+5:00  qm start 1012 (master3)
  T+6:00  All 3 etcd members healthy, full redundancy restored

_____________________________________________________________________

[References]
- kubernetes/dev/deployments/infrastructure/storage/nfs-csi-driver.yaml
- Proxmox VMIDs: 1010 (master1), 1011 (master2), 1012 (master3)
- CoreDNS ClusterIP: 10.96.0.10
