# TS-K8S-020 | 2026-04-10 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / Monitoring
Sub-techs: Grafana, Loki, Promtail, kube-prometheus-stack, loki-stack,
           HelmRelease, datasource health check, version compatibility
Environment: DEV k8s-dev cluster | monitoring namespace
             Grafana 12.4.2 (kube-prometheus-stack), Loki 2.9.x (loki-stack 2.10.2)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Grafana datasource health check fails. Loki API works via curl but Grafana
cannot connect.

  Grafana datasource health check error:
  parse error at line 1, col 1: syntax error: unexpected IDENTIFIER

Impact: cannot configure Loki datasource in Grafana, log aggregation
unavailable through Grafana UI, monitoring stack partially non-functional.

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Verified Loki API works directly from inside Grafana pod:

Command:
  kubectl exec -n monitoring deploy/kube-prometheus-stack-grafana -c grafana -- \
    curl -s http://loki:3100/loki/api/v1/labels

Output:
  Valid JSON response — Loki API is responding correctly.

Checked Grafana logs for the parse error:

Command:
  kubectl logs deploy/kube-prometheus-stack-grafana -n monitoring -c grafana \
    | grep -i loki

Output:
  parse error at line 1, col 1: syntax error: unexpected IDENTIFIER

Loki API responds to curl but fails on Grafana health check query.
Grafana 12.x sends health check queries using syntax Loki 2.x does not
understand. Version incompatibility between modern Grafana and legacy Loki.

loki-stack chart is deprecated and bundles Loki 2.x — incompatible with
Grafana 12.x query syntax.


# Suspected Root Cause
Grafana 12.x health check query syntax is incompatible with Loki 2.x.
loki-stack chart (2.10.2) bundles Loki 2.9.x which is a deprecated version
that does not understand modern Grafana query expectations.


# More Checks Notes:
N/A — version incompatibility confirmed from Grafana logs and chart versions.


# Suspected Solution
Upgrade from loki-stack chart (Loki 2.x) to loki chart (Loki 3.x) which is
compatible with Grafana 12.x. Deploy Promtail as a separate chart since loki
chart does not bundle it.


# Test
Upgraded to loki chart 6.29.0 (Loki 3.x), deployed promtail separately.
Checked Grafana datasource health check.

Result: PASS — datasource health check passes, log queries working in Grafana Explore.

_____________________________________________________________________

[Final Root Cause]
Grafana 12.x sends datasource health check queries using syntax that Loki 2.x
does not understand. loki-stack chart 2.10.2 bundles Loki 2.9.x — a deprecated
chart with an incompatible legacy version. Upgrading to Loki 3.x resolves the
syntax incompatibility.

_____________________________________________________________________

[Final Solution]
Upgraded from loki-stack (Loki 2.x) to loki chart (Loki 3.x):

  Old: chart: loki-stack, version: 2.10.2  (Loki 2.9.x)
  New: chart: loki,       version: 6.29.0  (Loki 3.x)

Key config changes for Loki 3.x:

  1. Deployment mode (required):
       deploymentMode: SingleBinary

  2. Retention requires delete_request_store:
       loki:
         compactor:
           retention_enabled: true
           delete_request_store: filesystem

  3. Disable heavy cache components (resource-constrained cluster):
       chunksCache:
         enabled: false
       resultsCache:
         enabled: false

  4. Promtail deployed as separate HelmRelease:
       chart: promtail
       version: 6.16.6

Files changed:
  kubernetes/*/deployments/apps/logging/helm-release.yaml

Verified: Yes

_____________________________________________________________________

[Risk Level] MEDIUM
Note: Loki 3.x has different config structure than 2.x — requires config
migration. Brief monitoring downtime during upgrade. Existing log data may
need migration depending on storage backend.

_____________________________________________________________________

[References]
- https://github.com/grafana/loki/tree/main/production/helm/loki
- https://github.com/grafana/helm-charts/tree/main/charts/promtail

_____________________________________________________________________

[Draft Notes]

Key lessons:
  1. loki-stack is deprecated — use separate loki + promtail charts going forward
  2. Check version compatibility matrix before upgrading Grafana ecosystem tools
  3. Always verify datasource health checks after any Grafana/Loki upgrades
  4. Loki 3.x has different config structure than 2.x — plan migration carefully

Commands reference:
  kubectl exec -n monitoring deploy/kube-prometheus-stack-grafana -c grafana -- \
    curl -s http://loki:3100/loki/api/v1/labels
  kubectl logs deploy/kube-prometheus-stack-grafana -n monitoring -c grafana \
    | grep -i loki
  kubectl exec -n monitoring deploy/loki -- loki --version