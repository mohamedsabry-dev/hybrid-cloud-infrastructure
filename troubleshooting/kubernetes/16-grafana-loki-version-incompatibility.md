# Grafana 12.x + Loki 2.x Health Check Failure

## Symptom
Grafana datasource health check fails with:
```
parse error at line 1, col 1: syntax error: unexpected IDENTIFIER
```

Loki API works via curl but Grafana can't connect.

## Environment
- Grafana 12.4.2 (kube-prometheus-stack)
- Loki 2.9.x (loki-stack chart 2.10.2)

## Root Cause
Grafana 12.x sends health check queries using syntax that Loki 2.x doesn't understand. Version incompatibility between modern Grafana and legacy Loki.

## Diagnosis
```bash
# Verify Loki API works
kubectl exec -n monitoring deploy/kube-prometheus-stack-grafana -c grafana -- \
  curl -s http://loki:3100/loki/api/v1/labels

# Check Grafana logs for parse error
kubectl logs deploy/kube-prometheus-stack-grafana -n monitoring -c grafana | grep -i loki
```

## Solution
Upgrade from `loki-stack` (Loki 2.x) to `loki` chart (Loki 3.x):

```yaml
# Old (loki-stack 2.10.2 = Loki 2.9.x)
chart: loki-stack
version: "2.10.2"

# New (loki 6.29.0 = Loki 3.x)
chart: loki
version: "6.29.0"
```

### Key Config Changes for Loki 3.x

1. **Deployment mode**:
```yaml
deploymentMode: SingleBinary
```

2. **Retention requires delete_request_store**:
```yaml
loki:
  compactor:
    retention_enabled: true
    delete_request_store: filesystem
```

3. **Disable heavy cache components** (for resource-constrained clusters):
```yaml
chunksCache:
  enabled: false
resultsCache:
  enabled: false
```

4. **Promtail deployed separately**:
```yaml
# Separate HelmRelease for promtail chart
chart: promtail
version: "6.16.6"
```

## Files Changed
- `kubernetes/*/deployments/apps/logging/helm-release.yaml`

## Lesson Learned
- Check version compatibility when using multiple Grafana ecosystem tools
- loki-stack is deprecated; use separate loki + promtail charts
- Loki 3.x has different config structure than 2.x
