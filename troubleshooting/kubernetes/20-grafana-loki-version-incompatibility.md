# TS-K8S-020 | 2026-04-10 | RESOLVED

## 1. Context

**System:** Grafana + Loki monitoring stack on Kubernetes

**Environment:**
- Grafana 12.4.2 (kube-prometheus-stack)
- Loki 2.9.x (loki-stack chart 2.10.2)

**Related Components:**
- kube-prometheus-stack Helm chart
- loki-stack Helm chart
- Promtail log collector

**Discovered During:** Grafana datasource health check configuration

---

## 2. Issue

**Symptom:**
Grafana datasource health check fails with:
```
parse error at line 1, col 1: syntax error: unexpected IDENTIFIER
```

Loki API works via curl but Grafana can't connect.

**Impact:**
- Unable to configure Loki as a datasource in Grafana
- Log aggregation/querying unavailable through Grafana UI
- Monitoring stack partially non-functional

---

## 3. Analysis

### Verify Loki API works directly
```bash
# Verify Loki API works
kubectl exec -n monitoring deploy/kube-prometheus-stack-grafana -c grafana -- \
  curl -s http://loki:3100/loki/api/v1/labels
```

### Check Grafana logs for parse error
```bash
kubectl logs deploy/kube-prometheus-stack-grafana -n monitoring -c grafana | grep -i loki
```

**Findings:** Loki API responds correctly to curl requests, but Grafana's health check query syntax is incompatible with Loki 2.x.

---

## 4. Root Cause

Grafana 12.x sends health check queries using syntax that Loki 2.x doesn't understand. Version incompatibility between modern Grafana and legacy Loki.

The loki-stack chart is deprecated and bundles Loki 2.x, which is incompatible with Grafana 12.x query syntax expectations.

---

## 5. Solution

### Solution Applied
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

### Files Changed
- `kubernetes/*/deployments/apps/logging/helm-release.yaml`

### Prevention Measures
- Check version compatibility matrix before upgrading Grafana ecosystem tools
- Pin chart versions in HelmRelease manifests
- Test datasource health checks after any Grafana/Loki upgrades

---

## 6. Solution Risk

**Risk Level:** Medium

**Potential Impact:**
- Loki 3.x has different config structure than 2.x - requires config migration
- Promtail must be deployed as separate chart
- Existing log data may need migration depending on storage backend
- Brief monitoring downtime during upgrade

---

## 7. Impact After Fix

**Observed Results:**
- Grafana datasource health check passes
- Log queries work correctly in Grafana Explore
- Loki 3.x provides improved performance and compatibility

---

## 8. Notes

### Lessons Learned
- Check version compatibility when using multiple Grafana ecosystem tools
- loki-stack is deprecated; use separate loki + promtail charts
- Loki 3.x has different config structure than 2.x
- Always verify datasource health checks after stack upgrades

### Commands Reference
```bash
# Verify Loki API
kubectl exec -n monitoring deploy/kube-prometheus-stack-grafana -c grafana -- \
  curl -s http://loki:3100/loki/api/v1/labels

# Check Grafana logs
kubectl logs deploy/kube-prometheus-stack-grafana -n monitoring -c grafana | grep -i loki

# Check Loki version
kubectl exec -n monitoring deploy/loki -- loki --version
```

### Related Files
- `kubernetes/*/deployments/apps/logging/helm-release.yaml`

### References
- [Grafana Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Loki Helm Chart](https://github.com/grafana/loki/tree/main/production/helm/loki)
- [Promtail Helm Chart](https://github.com/grafana/helm-charts/tree/main/charts/promtail)

---

## 9. Workaround

No temporary workaround available - upgrading to Loki 3.x is required for Grafana 12.x compatibility.

Alternative: Downgrade Grafana to a version compatible with Loki 2.x (not recommended due to security updates).
