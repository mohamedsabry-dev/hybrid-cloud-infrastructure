# TS-K8S-059 | 2026-05-02 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / Monitoring / etcd
Sub-techs: etcd, kube-prometheus-stack, Prometheus scraping, kubeadm manifests
Environment: PROD k8s cluster | 3 masters (kubeadm)
Re-opened: No
Related: TS-K8S-039 (original false alarm discovery), TS-K8S-054 (scheduler/controller-manager fix), TS-K8S-058 (kube-proxy fix)

_____________________________________________________________________

[Issue Description]
3 etcd false alarms firing continuously in Alertmanager since April 18.
These were the last remaining alerts from the original TS-K8S-039 batch.
Scheduler, controller-manager, and kube-proxy were already fixed in
TS-K8S-054 and TS-K8S-058. etcd was deferred because it needs cert
config or a metrics port — not just a bind-address change.

Alerts firing:
  - TargetDown (job="kube-etcd") — 100% targets down
  - etcdMembersDown — members are down (3)
  - etcdInsufficientMembers — insufficient members (0), severity: critical

All false — etcd is healthy, Prometheus just can't scrape it.

_____________________________________________________________________

[Analysis]

etcd was already configured with --listen-metrics-urls but bound to
127.0.0.1 only:

  --listen-metrics-urls=http://127.0.0.1:2381

Same on all 3 masters. Prometheus runs on a worker node so it can't
reach localhost on the masters. Two options considered:

  Option A: Give Prometheus the etcd client certs to scrape port 2379
  over TLS. Rejected — the healthcheck-client cert can read/write etcd
  data, not just metrics. Putting that cert in a Secret on a worker node
  widens the blast radius if Prometheus is compromised.

  Option B: Change 127.0.0.1 to 0.0.0.0 on the metrics port (2381).
  This exposes only /metrics and /health — no data access, no certs
  needed. Chose this — safer and simpler.

_____________________________________________________________________

[Fix Applied — Step 1: Manifest Change]

Changed --listen-metrics-urls on all 3 masters, one at a time:

  sed -i 's|http://127.0.0.1:2381|http://0.0.0.0:2381|' /etc/kubernetes/manifests/etcd.yaml

Order: master3 → master1 → master2

Each edit triggers kubelet to restart the etcd static pod. During restart,
the local apiserver loses its gRPC connection to etcd and logs
"connection refused" errors for ~10-20 seconds until etcd comes back.

Impact verification — confirmed each restart was isolated to one node:

  Loki query:
    {namespace="kube-system", pod="kube-apiserver-k8s-master3.lab.local"} |= "connection refused"
    {namespace="kube-system", pod="kube-apiserver-k8s-master2.lab.local"} |= "connection refused"
    {namespace="kube-system", pod="kube-apiserver-k8s-master1.lab.local"} |= "connection refused"

  Result: ~700 error lines per node during its own etcd restart window.
  Other 2 masters showed zero "connection refused" during that window.
  Quorum maintained throughout — only local apiserver impacted.

Cross-master signal — apiserver endpoint lease resets confirmed the
rolling restart pattern:

  11:34:25 — Resetting endpoints to [10.0.51.10, 10.0.51.11]
             master3 (.12) etcd restarting
  11:35:12 — Resetting endpoints to [10.0.51.10, 10.0.51.11, 10.0.51.12]
             master3 back
  11:35:56 — Resetting endpoints to [10.0.51.11, 10.0.51.12]
             master1 (.10) etcd restarting
  11:36:48 — Resetting endpoints to [10.0.51.10, 10.0.51.11, 10.0.51.12]
             master1 back
  11:39:27 — Resetting endpoints to [10.0.51.10, 10.0.51.12]
             master2 (.11) etcd restarting
  11:40:12 — Resetting endpoints to [10.0.51.10, 10.0.51.11, 10.0.51.12]
             master2 back

  Loki query used:
    {namespace="kube-system", pod=~"kube-apiserver.*"} |= "Resetting endpoints for master service"

Each master removed from endpoints during its restart, re-added within
~1 minute. Clean rolling restart — cluster never lost quorum.

_____________________________________________________________________

[Fix Verification — Step 2: Helm Config Already Correct]

Assumed we'd need to edit the kube-prometheus-stack helm values to
point at port 2381. Turns out the Helm chart already had it configured
correctly from the initial deployment — the only problem was etcd
binding to 127.0.0.1.

Confirmed by tracing the full scrape chain:

  1. ServiceMonitor targets port named "http-metrics":
     kubectl get servicemonitor kube-prometheus-stack-kube-etcd -n monitoring -o yaml
       spec.endpoints[0].port: http-metrics

  2. Service maps "http-metrics" to port 2381:
     kubectl get service kube-prometheus-stack-kube-etcd -n kube-system -o yaml
       spec.ports[0].name: http-metrics
       spec.ports[0].port: 2381
       spec.ports[0].targetPort: 2381
       spec.selector: component: etcd

  3. Endpoints resolve to all 3 masters:
     kubectl get endpoints kube-prometheus-stack-kube-etcd -n kube-system
       10.0.51.10:2381, 10.0.51.11:2381, 10.0.51.12:2381

  4. Metrics endpoint reachable:
     curl http://10.0.51.10:2381/metrics | head -5
       # HELP etcd_cluster_version Which version is running.
       # TYPE etcd_cluster_version gauge
       etcd_cluster_version{cluster_version="3.6"} 1

The entire pipeline was already wired: ServiceMonitor → Service → Endpoints
→ port 2381. The only missing piece was etcd itself binding to 127.0.0.1
instead of 0.0.0.0.

After the manifest change in step 1, Prometheus scraped successfully
within ~60 seconds. All 3 alerts (TargetDown, etcdMembersDown,
etcdInsufficientMembers) resolved automatically in Alertmanager.

_____________________________________________________________________

[Final Root Cause]

The fix was one line on 3 masters:
  127.0.0.1:2381 → 0.0.0.0:2381

Everything else — the ServiceMonitor, the headless Service, the endpoint
discovery, the port mapping — was already correctly configured by
kube-prometheus-stack since day one (April 9). The chart anticipated
kubeadm clusters using port 2381 for etcd metrics. The only assumption
it couldn't enforce was that etcd would actually listen on a routable
address.

This also means: if I ever reinstall the monitoring stack or upgrade the
chart, this fix survives — the helm side doesn't need touching. Only
the etcd manifests on the masters need the 0.0.0.0 binding.

_____________________________________________________________________

[Post-Fix Alert — Normal, Self-Resolved]

After the 3 false alarms cleared, a new alert fired:

  etcdHighNumberOfLeaderChanges:
  "etcd cluster kube-etcd: 4.54 leader changes within the last 15 minutes."

This is normal — we restarted etcd on 3 masters within a 6-minute
window (master3 at 11:34, master1 at 11:35, master2 at 11:39). Each
restart triggers a leader election. 3 restarts in quick succession =
high leader change count in the 15-minute sliding window. Not a sign
of resource pressure or instability — just the rolling restart we did.
Self-resolved once the 15-minute window rolled past.

_____________________________________________________________________

[Risk Level] LOW

Metrics-only port, no data access, no TLS credentials exposed.
Rolling restart confirmed isolated per-node — no cluster-wide impact.

_____________________________________________________________________

[References]
- TS-K8S-039 — original false alarm discovery and root cause
- TS-K8S-054 — scheduler + controller-manager bind-address fix
- TS-K8S-058 — kube-proxy metricsBindAddress fix
