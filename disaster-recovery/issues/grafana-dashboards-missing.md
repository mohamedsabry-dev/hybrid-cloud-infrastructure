# Issue: Grafana Provisioned Dashboards Not Loading

**Status:** OPEN
**Date Discovered:** 2026-04-18
**Severity:** Medium (monitoring affected, not critical)

---

## Summary

Grafana UI only shows manually imported dashboards (Node Exporter). The provisioned dashboards from kube-prometheus-stack are not visible, even though:
- ConfigMaps with `grafana_dashboard=1` label exist
- Sidecar has copied JSON files to `/tmp/dashboards/`
- Provisioner config exists at `/etc/grafana/provisioning/dashboards/sc-dashboardproviders.yaml`

---

## Symptoms

**Visible in Grafana:**
- Node Exporter / MacOS
- Node Exporter Full

**Missing (should be ~27 dashboards):**
- Kubernetes cluster dashboards
- Node dashboards
- Prometheus dashboards
- etc.

---

## Investigation Done

```bash
# ConfigMaps exist
kubectl get cm -n monitoring -l grafana_dashboard=1
# Shows 27 ConfigMaps

# JSON files exist in container
kubectl exec -it <grafana-pod> -n monitoring -c grafana -- ls -la /tmp/dashboards/
# Shows 27 JSON files

# Provisioner config exists
kubectl exec -it <grafana-pod> -n monitoring -c grafana -- cat /etc/grafana/provisioning/dashboards/sc-dashboardproviders.yaml
# Shows config pointing to /tmp/dashboards
```

---

## Possible Causes

1. Grafana not reading provisioner config on startup
2. Multiple replicas (3) with inconsistent state
3. Error parsing dashboard JSONs
4. Database/cache issue

---

## TODO

1. Restart Grafana deployment:
   ```bash
   kubectl rollout restart deployment kube-prometheus-stack-grafana -n monitoring
   ```

2. Check Grafana logs for errors:
   ```bash
   kubectl logs -l app.kubernetes.io/name=grafana -n monitoring -c grafana | grep -i "dashboard\|provision\|error"
   ```

3. Check if dashboards appear after restart

4. If still missing, check Grafana database/persistence

---

## Context

Actions taken before issue noticed:
- Imported Node Exporter template manually
- Deleted stack alertmanager
- Disabled stack alertmanager in helm-release

---

## Related Files

- `monitoring/helm-release.yaml` - Grafana config
- Dashboard ConfigMaps in monitoring namespace
