Skill 10 — Monitoring (6 questions)
=====================================

Format: Standard questions only. Project examples are ammunition.
Your Prometheus + Grafana + Loki + Alertmanager stack, three alert
paths (Prometheus→AM, remediation→AM, host scripts→postfix),
decoupled Alertmanager with Vault-injected SMTP, event-exporter,
external scrape targets, IO storm evidence emails — inject when earned.

---

1. What is Prometheus and how does it work?

   Coverage check:
   - pull model (scrapes targets at intervals)
   - TSDB (time-series database), retention, storage
   - service discovery (static, K8s, file-based)
   - exporters (node-exporter, blackbox-exporter, custom)
   - PromQL basics (rate, irate, histogram_quantile, aggregation)
   - recording rules (pre-computed expensive queries)
   - push vs pull model tradeoffs
   - cardinality — what it is, why explosion is dangerous, relabeling to control it

2. How do you set up alerting — Alertmanager, routing, and managing alert fatigue?

   Coverage check:
   - Alertmanager architecture (routing tree, receivers)
   - grouping (batch related alerts)
   - inhibition (suppress lower-severity when higher fires)
   - silences (planned maintenance)
   - deduplication
   - alert fatigue — strategies to reduce noise
   - symptom-based vs cause-based alerts
   - severity tiers (critical/page vs warning/ticket)
   - runbook linking

3. What's the difference between monitoring and observability?

   Coverage check:
   - monitoring — known-unknowns (predefined checks)
   - observability — unknown-unknowns (explore and diagnose)
   - three pillars: metrics, logs, traces
   - golden signals (latency, traffic, errors, saturation)
   - RED method (Rate, Errors, Duration) for services
   - USE method (Utilization, Saturation, Errors) for infrastructure
   - SLIs, SLOs, error budgets
   - blackbox vs whitebox monitoring

4. An alert is firing but the service seems fine. How do you investigate?

   Coverage check:
   - check the alert expression — is the query correct?
   - check the time window — stale data? lag?
   - check the target — is Prometheus scraping the right endpoint?
   - check for metric name/label changes after upgrade
   - check thresholds — too sensitive?
   - check for flapping (alert fires/resolves repeatedly)
   - false positive vs real problem you're not seeing
   - "service seems fine" — verify from the user's perspective, not just internal

5. How do you monitor infrastructure — from Linux servers to Kubernetes?

   Coverage check:
   - node-exporter (CPU, memory, disk, network on Linux)
   - kube-state-metrics (K8s object states — pods, deployments, nodes)
   - metrics-server (CPU/memory for HPA and kubectl top)
   - cAdvisor (container-level resource usage)
   - Grafana dashboards (datasources, variables, provisioning as code)
   - external target monitoring (Vault, FreeIPA, NAS — scrape configs)

6. How does log aggregation work — and how does it complement metrics?

   Coverage check:
   - logs for context, metrics for trends
   - EFK stack (Elasticsearch + Fluentd + Kibana)
   - PLG stack (Promtail + Loki + Grafana)
   - Loki vs Elasticsearch (label-indexed vs full-text-indexed)
   - structured logging — why it matters for parsing
   - log shipping architecture (agent on node → aggregator → storage)
   - correlating logs with metrics (same timestamp, same labels)
   - K8s pod logs from /var/log/pods/
