Observability Alert Pipeline — Metric Scrape to Email Notification (Summary Trace)
====================================================================================

pre-trace (one-time setup):
  kube-prometheus-stack: Prometheus + Grafana + node-exporter + kube-state-metrics
    → standalone Alertmanager on control-plane (Vault-templated SMTP config)
    → Loki (SingleBinary) + Promtail (DaemonSet all nodes) + event-exporter
    → Vault secrets for Grafana admin creds and Alertmanager SMTP

metrics collection (every 30s):
  → Prometheus scrapes auto-discovered targets via ServiceMonitor CRDs
    → kubelet, kube-apiserver, kube-state-metrics, node-exporter, CoreDNS, etcd
    → external nodes (7 hosts) via additionalScrapeConfigs (job="external-nodes")
      → stored in TSDB on NFS (dev 20Gi / prod 50Gi, 15-day retention)

alert evaluation:
  → Prometheus evaluates PrometheusRule CRDs (custom + ~100 built-in)
    → ExternalNodeDown: up{job="external-nodes"} == 0 for 2m
    → PodCrashLooping: restarts > 5 in 1h for 5m
    → KubernetesNodeCriticalCPU: CPU > 95% for 2m
      → expression matches → "for" timer → pending → firing

→ firing alert pushed to Alertmanager (alertmanager.monitoring.svc:9093)
  → route: Watchdog → null, everything else → email-alerts
    → group_by: [namespace], group_wait: 30s, repeat: 4h
    → inhibit: critical suppresses warning/info (prevents storm)
      → Gmail SMTP (creds from Vault) → send_resolved: true

log collection:
  → Promtail DaemonSet mounts /var/log/pods/ → CRI parse → label extract
    → push to Loki /loki/api/v1/push (near real-time)
  → event-exporter watches K8s events → push to Loki (job="kube-events")
    → Loki stores: TSDB v13, dev 7d / prod 14d retention

→ Grafana queries 3 datasources: Prometheus (PromQL), Loki (LogQL), Alertmanager
  → 1 replica only (TS-K8S-037: SQLite corruption with NFS multi-writer)
  → ingress: grafana-{env}.lab.local

three alert paths → same inbox:
  → Path A: Prometheus → Alertmanager → Gmail (K8s workload alerts)
  → Path B: remediation pod → Alertmanager API → Gmail (node health actions)
  → Path C: bash scripts → postfix → Gmail relay (host hardware alerts)
    → no unified channel, no PagerDuty/Slack, email only
