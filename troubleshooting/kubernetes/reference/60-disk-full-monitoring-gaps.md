# TS-K8S-060 | 2026-05-03 | OPEN | IMPROVEMENT
_____________________________________________________________________

[Info]
Domain: Kubernetes / Monitoring / Alerting
Sub-techs: node-exporter, Prometheus, Alertmanager, event-exporter, DaemonSet eviction
Environment: dev + prod
Re-opened: No

_____________________________________________________________________

[Issue Description]
Discovered during DR test: worker-disk-full-root-filesystem (2026-05-03).

Two monitoring gaps exposed when worker3 hit 100% disk:

Gap 1 — Node-exporter dies before disk alert fires:
  Node-exporter is a DaemonSet with no special priority class. When kubelet
  hits disk pressure, it evicts monitoring pods first (lower priority) before
  app pods. The "disk full" alert depends on node-exporter metrics — but
  node-exporter is already dead by the time the threshold would fire.

  Eviction order observed:
    1. Monitoring DaemonSets (node-exporter, promtail, loki-canary)
    2. App pods (WordPress, event-exporter)
    3. Test pods (default priority 0)
    4. kube-system critical pods — NEVER evicted

  Result: Prometheus gets no disk metric → alert never fires → silence
  looks like "all clear" instead of "something is wrong."

Gap 2 — Event exporter is a single replica:
  Event exporter was running on worker3 (1 replica). When it got evicted,
  the ReplicaSet rescheduled to worker2 — brief gap in event logging but
  not total loss. If it had been on the only healthy worker during a
  multi-node event, we'd lose event visibility entirely.

_____________________________________________________________________

[Analysis]
# From DR test evidence:

Node-exporter evicted at 20:51:45 during disk pressure:
  FailedDaemonPod  node-exporter DaemonSet — "will try to kill it"

After eviction, Prometheus had no disk metrics for worker3.
No KubeDiskFull alert fired. Only alerts received were:
  - KubeNodeEviction (imagefs.available, nodefs.available) — from API server
  - RemediationAction (reboot initiated, recovery) — from remediation pod

The eviction alerts came from the control plane (watching node conditions),
not from node-exporter. So Prometheus saw the aftermath, not the cause.

Event exporter rescheduled successfully:
  event-exporter-57769d9b74-xq7sz  1/1  Running  0  3m21s  k8s-worker2.lab.local

But the gap between eviction and reschedule meant kube-events had a
~3 minute blind spot in Loki.

_____________________________________________________________________

[Potential Solutions]

Fix 1 — Absent metric alert (node-exporter silence = the signal):
  Add PrometheusRule: if node_filesystem_avail_bytes is absent for a node
  for >5 minutes, fire alert. Silence itself becomes the evidence.

  ```yaml
  - alert: NodeExporterDown
    expr: |
      up{job="node-exporter"} == 0
      or
      absent_over_time(up{job="node-exporter"}[5m])
    for: 3m
    labels:
      severity: critical
    annotations:
      summary: "Node exporter stopped reporting on {{ $labels.instance }}"
      description: "Possible disk pressure eviction — node-exporter dies before disk alert can fire"
  ```

Fix 2 — Scale event-exporter to 2 replicas:
  Currently 1 replica. Scale to 2 with pod anti-affinity to spread across
  workers. Event exporter is stateless (reads from API server, pushes to
  Loki) — no storage dependency, no extra config needed. Scale via Flux
  manifest update.

Fix 3 — Consider elevating node-exporter priority class:
  Could give node-exporter a higher priority so it survives longer during
  disk pressure. Tradeoff: keeping a metric reporter alive while actual
  workloads get evicted. The absent metric alert (Fix 1) is the better
  approach — it catches the failure without gaming the eviction order.

_____________________________________________________________________

[Final Root Cause]
Kubelet eviction priority doesn't account for monitoring dependencies.
Node-exporter and promtail are regular DaemonSets with no special
priority, so they get evicted before the alert they should trigger can
fire. Event exporter is a single replica — one node failure creates a
monitoring gap.

_____________________________________________________________________

[Final Solution]
PENDING — fixes identified, not yet applied.

_____________________________________________________________________

[Risk Level] MEDIUM — disk pressure events go undetected until node
hits NotReady. Remediation pod catches it eventually but the root cause
(disk full) is invisible to the alerting stack.

_____________________________________________________________________

[References]
- Source: disaster-recovery/worker-disk-full-root-filesystem.md (DR test 2026-05-03)
- Related: TS-K8S-016 (pod priority classes — DR readiness)
- Related: scheduler-failure-full-kill.md (event-exporter deployed after that DR test)
- Related: TS-LNX-006 (/var not separate partition — root cause of disk filling)
- Code: kubernetes/dev/deployments/apps/event-exporter/ (scale config)
- Code: kubernetes/dev/deployments/infrastructure/kube-prometheus-stack/ (alert rules)
