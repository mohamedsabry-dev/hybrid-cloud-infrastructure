# Issue: Custom PrometheusRule Not Picked Up by Prometheus

**Status:** RESOLVED
**Date Discovered:** 2026-04-18
**Resolution:** Added missing `release: kube-prometheus-stack` label

---

## Summary

Custom PrometheusRule CRD (`custom-alerts`) was applied to cluster but Prometheus was not evaluating the rules. Built-in `TargetDown` alert fired instead of custom `ExternalNodeDown` alert.

---

## Symptoms

- Applied `custom-alerts` PrometheusRule 13 hours ago
- Shut down external node to test
- Received generic `TargetDown` alert (built-in) instead of custom `ExternalNodeDown`
- Custom alert has specific labels (`instance`, `role`) that weren't appearing

**Built-in alert received:**
```
alertname = TargetDown
job = external-nodes
description = 14.29% of the external-nodes/ targets in namespace are down.
```

**Expected custom alert:**
```
alertname = ExternalNodeDown
instance = local-runner.lab.local
role = automation
description = automation node unreachable for 2 minutes
```

---

## Root Cause

kube-prometheus-stack's Prometheus has a `ruleSelector` that filters which PrometheusRule CRDs it loads:

```bash
kubectl get prometheus -n monitoring -o jsonpath='{.items[0].spec.ruleSelector}'
# Output: {"matchLabels":{"release":"kube-prometheus-stack"}}
```

The custom-alerts PrometheusRule was missing this label:

**Before (not working):**
```yaml
metadata:
  name: custom-alerts
  namespace: monitoring
  labels:
    app.kubernetes.io/name: prometheus
    environment: dev
```

**After (working):**
```yaml
metadata:
  name: custom-alerts
  namespace: monitoring
  labels:
    release: kube-prometheus-stack  # REQUIRED
    app.kubernetes.io/name: prometheus
    environment: dev
```

---

## How PrometheusRule Works

```
PrometheusRule CRD applied to cluster
    ↓
Prometheus Operator watches for PrometheusRule resources
    ↓
Filters by ruleSelector (requires matching labels)
    ↓
Generates prometheus config and reloads Prometheus
    ↓
Prometheus evaluates rules in groups
```

**Alert evaluation flow:**
```
expr: up{job="external-nodes"} == 0
    ↓
Prometheus scrapes target every 30s
    ↓
If scrape fails, up metric = 0
    ↓
Alert enters PENDING state, starts "for" timer (2m)
    ↓
After 2m still true → FIRING
    ↓
Labels from metric ($labels.instance, $labels.role) injected into annotations
    ↓
Sent to Alertmanager → email/slack/etc
```

---

## Solution Verified - Evidence

After adding `release: kube-prometheus-stack` label and re-applying, **both alerts now fire**:

**Custom ExternalNodeDown (working):**
```
alertname = ExternalNodeDown
instance = local-runner.lab.local        ← Custom label from scrape config
job = external-nodes
prometheus = monitoring/kube-prometheus-stack-prometheus
role = automation                        ← Custom label from scrape config
severity = critical

Annotations:
  description = automation node unreachable for 2 minutes
  summary = local-runner.lab.local is down
```

**Built-in TargetDown (also fires):**
```
alertname = TargetDown
job = external-nodes
prometheus = monitoring/kube-prometheus-stack-prometheus
severity = warning

Annotations:
  description = 14.29% of the external-nodes/ targets in namespace are down.
  summary = One or more targets are unreachable.
```

**Key difference:**
- `ExternalNodeDown` has specific `instance` and `role` labels from the scrape config
- `TargetDown` is generic percentage-based alert from kube-prometheus-stack
- Both are useful: custom for specific node identification, built-in for overall health

---

## Verification Commands

```bash
# Check PrometheusRule exists with correct labels
kubectl get prometheusrule custom-alerts -n monitoring -o yaml | grep -A5 labels

# Check rules loaded in Prometheus
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
# Visit http://localhost:9090/rules → search for "ExternalNodeDown"

# Check alerts firing
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
# Visit http://localhost:9090/alerts
```

---

## Files Modified

- `kubernetes/dev/deployments/apps/monitoring/custom-alerts.yaml` - Added `release: kube-prometheus-stack` label

---

## Lesson Learned

When creating custom PrometheusRule CRDs for kube-prometheus-stack, always include:
```yaml
labels:
  release: kube-prometheus-stack
```

This label is required for the Prometheus Operator to pick up the rules.
