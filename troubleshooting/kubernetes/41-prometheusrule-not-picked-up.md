# TS-K8S-041 | 2026-04-18 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / Monitoring / Prometheus
Sub-techs: PrometheusRule CRD, Prometheus Operator, ruleSelector,
           kube-prometheus-stack, custom alerts, label matching
Environment: DEV k8s cluster | kube-prometheus-stack
Discovered during: Testing custom ExternalNodeDown alert
Related: TS-K8S-042 (discovered during same session)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Custom PrometheusRule CRD (`custom-alerts`) was applied to cluster but Prometheus
wasn't evaluating the rules. I shut down an external node to test — received the
generic built-in `TargetDown` alert instead of my custom `ExternalNodeDown` alert.

Built-in alert received:
```
alertname = TargetDown
job = external-nodes
description = 14.29% of the external-nodes/ targets in namespace are down.
```

Expected custom alert:
```
alertname = ExternalNodeDown
instance = local-runner.lab.local
role = automation
description = automation node unreachable for 2 minutes
```

_____________________________________________________________________

[Analysis]

# Step 1: Checked Prometheus ruleSelector

```
kubectl get prometheus -n monitoring -o jsonpath='{.items[0].spec.ruleSelector}'
# {"matchLabels":{"release":"kube-prometheus-stack"}}
```

Prometheus only loads PrometheusRule CRDs that match this label selector.

# Step 2: Checked custom-alerts labels — missing required label

Before (not working):
```yaml
metadata:
  name: custom-alerts
  namespace: monitoring
  labels:
    app.kubernetes.io/name: prometheus
    environment: dev
```

Missing `release: kube-prometheus-stack` label. Prometheus Operator filters by
this label and ignores any PrometheusRule without it.

_____________________________________________________________________

[Final Root Cause]
Custom PrometheusRule was missing the `release: kube-prometheus-stack` label.
kube-prometheus-stack's Prometheus has a `ruleSelector` that requires this label
on all PrometheusRule CRDs. Without it, the Operator ignores the rule entirely.

_____________________________________________________________________

[Final Solution]

Added the missing label:

```yaml
metadata:
  name: custom-alerts
  namespace: monitoring
  labels:
    release: kube-prometheus-stack  # REQUIRED
    app.kubernetes.io/name: prometheus
    environment: dev
```

After re-applying, both alerts fire:

Custom ExternalNodeDown:
```
alertname = ExternalNodeDown
instance = local-runner.lab.local
job = external-nodes
role = automation
severity = critical
description = automation node unreachable for 2 minutes
summary = local-runner.lab.local is down
```

Built-in TargetDown (also fires):
```
alertname = TargetDown
job = external-nodes
severity = warning
description = 14.29% of the external-nodes/ targets in namespace are down.
```

Both are useful — custom for specific node identification, built-in for overall
health.

File modified: `kubernetes/dev/deployments/apps/monitoring/custom-alerts.yaml`

Verified: Yes — custom PrometheusRule loaded, alerts firing correctly.

_____________________________________________________________________

[Risk Level] LOW

Label-only change, no impact on running resources.

_____________________________________________________________________

[References]
- TS-K8S-042 — Flux retry storm (discovered during same session)
