# Issue: Grafana Provisioned Dashboards Not Loading

**Status:** RESOLVED
**Date Discovered:** 2026-04-18
**Date Resolved:** 2026-04-18
**Severity:** Medium (monitoring affected, not critical)
**Root Cause:** SQLite database corruption due to multiple replicas writing to shared NFS storage

---

## Summary

Grafana UI only showed manually imported dashboards (Node Exporter). The 27 provisioned dashboards from kube-prometheus-stack were not visible, even though:
- ConfigMaps with `grafana_dashboard=1` label existed
- Sidecar had copied JSON files to `/tmp/dashboards/`
- Provisioner config existed at `/etc/grafana/provisioning/dashboards/sc-dashboardproviders.yaml`

---

## Root Cause Analysis

### The Problem
Grafana was configured with:
- **3 replicas** for high availability
- **NFS storage** (nfs-retain) with ReadWriteMany (RWX) access mode
- **SQLite database** (default Grafana embedded database)

SQLite uses file-level locking that does not work reliably over NFS. When multiple Grafana pods attempted concurrent writes to `grafana.db`, the database became corrupted.

### Evidence

Grafana logs showed repeated errors:
```
level=error msg="failed to save dashboard" file=/tmp/dashboards/k8s-resources-node.json
error="database disk image is malformed"
```

All 27 provisioned dashboards failed to save with the same error:
```
transactional operation: insert into resource: resource_insert.sql:
database disk image is malformed
```

---

## Investigation Timeline

### Step 1: Initial Checks
```bash
# Verified ConfigMaps exist (27 found)
kubectl get cm -n monitoring -l grafana_dashboard=1

# Verified JSON files exist in container
kubectl exec -it <grafana-pod> -n monitoring -c grafana -- ls -la /tmp/dashboards/
# Output: 27 JSON files present

# Verified provisioner config points to correct path
kubectl exec -it <grafana-pod> -n monitoring -c grafana -- \
  cat /etc/grafana/provisioning/dashboards/sc-dashboardproviders.yaml
# Output: path: /tmp/dashboards/
```

### Step 2: Attempted Fixes (Did Not Work)
- Rollout restart of Grafana deployment
- Scaling replicas from 3 to 1 with restart

These did not resolve the issue because the SQLite database was already corrupted.

### Step 3: Log Analysis - Found Root Cause
```bash
kubectl logs -l app.kubernetes.io/name=grafana -n monitoring -c grafana | grep -i "error"
```
**Result:** "database disk image is malformed" errors on all dashboard provisioning attempts.

### Step 4: Resolution
1. Paused Flux reconciliation:
   ```bash
   flux suspend helmrelease kube-prometheus-stack -n monitoring
   ```

2. Scaled Grafana to 0:
   ```bash
   kubectl scale deployment kube-prometheus-stack-grafana -n monitoring --replicas=0
   ```

3. Deleted corrupted database from NFS storage:
   ```bash
   rm /path/to/grafana/pvc/grafana.db
   ```

4. Scaled Grafana back to 1:
   ```bash
   kubectl scale deployment kube-prometheus-stack-grafana -n monitoring --replicas=1
   ```

5. Verified dashboards loaded successfully - all 27 provisioned dashboards appeared.

### Step 5: Reproduction Test (Confirmed Root Cause)
To confirm the root cause, we scaled back to 3 replicas:
```bash
kubectl scale deployment kube-prometheus-stack-grafana -n monitoring --replicas=3
```

**Result:** Database corruption occurred again within seconds:
```
level=error msg="failed to save dashboard" error="database disk image is malformed"
```

This confirmed that **SQLite + NFS + multiple writers = database corruption**.

---

## Resolution

### Permanent Fix Applied
Changed Grafana replicas from 3 to 1 in helm-release.yaml:
```yaml
grafana:
  replicas: 1  # Changed from 3 - SQLite cannot handle multiple writers on NFS
```

### Why Not External Database?
Considered using external MySQL/PostgreSQL for true HA, but:
- MariaDB is dedicated to WordPress stability
- Adding new database infrastructure adds complexity and creates another SPOF
- Single Grafana replica is acceptable for this environment (monitoring is not mission-critical)

### Flux Deployment Sequence
After updating helm-release.yaml, the fix was deployed using GitOps:

```bash
# 1. Commit and push changes
git add kubernetes/prod/deployments/apps/monitoring/helm-release.yaml \
        disaster-recovery/issues/grafana-dashboards-missing.md
git commit -m "fix(grafana): reduce replicas to 1 - SQLite corruption on NFS with multi-writer"
git push

# 2. Wait for Flux kustomizations to reconcile in order
flux reconcile kustomization flux-system --with-source
flux reconcile kustomization infrastructure
flux reconcile kustomization apps

# 3. Verify all kustomizations are ready
flux get kustomization
# NAME            REVISION                SUSPENDED       READY   MESSAGE
# apps            dev@sha1:xxxxxxxx       False           True    Applied revision: dev@sha1:xxxxxxxx
# flux-system     dev@sha1:xxxxxxxx       False           True    Applied revision: dev@sha1:xxxxxxxx
# infrastructure  dev@sha1:xxxxxxxx       False           True    Applied revision: dev@sha1:xxxxxxxx

# 4. Then resume the suspended HelmRelease
flux resume helmrelease kube-prometheus-stack -n monitoring
# ► resuming helmrelease kube-prometheus-stack in monitoring namespace
# ✔ helmrelease resumed
# ✔ HelmRelease kube-prometheus-stack reconciliation completed
# ✔ applied revision 82.18.0

# 5. Verify Grafana pod is running with 1 replica
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana
```

**Important:** Always wait for all kustomizations to reconcile BEFORE resuming the HelmRelease. This ensures Flux has the new config (1 replica) and won't reconcile with old values (3 replicas).

---

## Recommendations

### Before Destructive Operations - Export Dashboards

**Via Grafana UI:**
1. Open dashboard
2. Settings (gear icon) → JSON Model
3. Copy/Save the JSON

**Via API (bulk export):**
```bash
# List all dashboard UIDs
kubectl exec -it <grafana-pod> -n monitoring -c grafana -- \
  curl -s -u admin:PASSWORD http://localhost:3000/api/search | jq -r '.[].uid'

# Export specific dashboard
kubectl exec -it <grafana-pod> -n monitoring -c grafana -- \
  curl -s -u admin:PASSWORD http://localhost:3000/api/dashboards/uid/<UID> > backup.json
```

### Popular Node Dashboards to Import
If dashboards are lost, these can be imported from grafana.com:
- **Node Exporter Full** - ID: `1860`
- **Node Exporter for Prometheus** - ID: `11074`

Import via: Dashboards → New → Import → Enter ID → Load

### Future HA Considerations
If HA Grafana is required in the future, options include:
1. **External PostgreSQL/MySQL database** - Allows multiple Grafana replicas
2. **Different storage class** - Use block storage with proper locking instead of NFS
3. **Grafana Enterprise** - Has built-in HA clustering

---

## Configuration Reference

### Current Grafana Helm Values
```yaml
grafana:
  replicas: 1  # Single replica to avoid SQLite corruption

  persistence:
    enabled: true
    storageClassName: nfs-retain
    accessModes:
      - ReadWriteMany
    size: 10Gi
```

### Provisioner Configuration (auto-generated)
```yaml
# /etc/grafana/provisioning/dashboards/sc-dashboardproviders.yaml
apiVersion: 1
providers:
  - name: 'sidecarProvider'
    orgId: 1
    type: file
    disableDeletion: false
    allowUiUpdates: false
    updateIntervalSeconds: 30
    options:
      path: /tmp/dashboards
```

---

## Related Files

- `kubernetes/prod/deployments/apps/monitoring/helm-release.yaml` - Grafana config
- Dashboard ConfigMaps in monitoring namespace (label: `grafana_dashboard=1`)
- **This document:** `troubleshooting/kubernetes/37-grafana-dashboards-missing-sqlite-corruption.md`

---

## Lessons Learned

1. **SQLite is not suitable for multi-writer scenarios** - Especially over network filesystems like NFS
2. **Always check logs for database errors** - "database disk image is malformed" is a clear SQLite corruption indicator
3. **Test HA configurations thoroughly** - Scaling replicas without proper database backend can cause immediate corruption
4. **Export dashboards before major changes** - Provisioned dashboards will reload, but manually imported ones will be lost
