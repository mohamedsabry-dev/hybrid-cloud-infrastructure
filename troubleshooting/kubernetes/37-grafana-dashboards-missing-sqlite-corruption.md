# TS-K8S-037 | 2026-04-18 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / Grafana / Storage
Sub-techs: SQLite, NFS multi-writer, Grafana provisioned dashboards,
           kube-prometheus-stack, sidecar ConfigMaps, Flux HelmRelease
Environment: DEV k8s cluster | Grafana 3 replicas | NFS nfs-retain StorageClass
Discovered during: Checking Grafana dashboards after cluster recovery
Related: TS-K8S-036 (Grafana anti-affinity rollout stuck)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Grafana UI only showed manually imported dashboards (Node Exporter). The 27
provisioned dashboards from kube-prometheus-stack were not visible, even though:
- ConfigMaps with `grafana_dashboard=1` label existed
- Sidecar had copied JSON files to `/tmp/dashboards/`
- Provisioner config existed at `/etc/grafana/provisioning/dashboards/sc-dashboardproviders.yaml`

_____________________________________________________________________

[Analysis]

# Step 1: Initial checks

```
# Verified 27 ConfigMaps exist
kubectl get cm -n monitoring -l grafana_dashboard=1

# Verified JSON files exist in container
kubectl exec -it <grafana-pod> -n monitoring -c grafana -- ls -la /tmp/dashboards/
# Output: 27 JSON files present

# Verified provisioner config points to correct path
kubectl exec -it <grafana-pod> -n monitoring -c grafana -- \
  cat /etc/grafana/provisioning/dashboards/sc-dashboardproviders.yaml
# Output: path: /tmp/dashboards/
```

Everything looked correct. Dashboards were there, provisioner was configured,
but Grafana wouldn't load them.

# Step 2: Attempted fixes (didn't work)

- Rollout restart of Grafana deployment — didn't help
- Scaling replicas from 3 to 1 with restart — didn't help

These didn't work because the SQLite database was already corrupted.

# Step 3: Log analysis — found the root cause

```
kubectl logs -l app.kubernetes.io/name=grafana -n monitoring -c grafana | grep -i "error"
```

```
level=error msg="failed to save dashboard" file=/tmp/dashboards/k8s-resources-node.json
error="database disk image is malformed"
```

All 27 dashboards failed with:
```
transactional operation: insert into resource: resource_insert.sql:
database disk image is malformed
```

SQLite database corruption. Grafana was using SQLite (default embedded database)
with 3 replicas on NFS (ReadWriteMany). SQLite uses file-level locking that
doesn't work reliably over NFS. Multiple Grafana pods writing concurrently to
`grafana.db` corrupted it.

# Step 4: Resolution

1. Suspended Flux: `flux suspend helmrelease kube-prometheus-stack -n monitoring`
2. Scaled to 0: `kubectl scale deployment kube-prometheus-stack-grafana -n monitoring --replicas=0`
3. Deleted corrupted database from NFS storage: `rm /path/to/grafana/pvc/grafana.db`
4. Scaled to 1: `kubectl scale deployment kube-prometheus-stack-grafana -n monitoring --replicas=1`
5. All 27 provisioned dashboards appeared.

# Step 5: Reproduction test (confirmed root cause)

Scaled back to 3 replicas to confirm:
```
kubectl scale deployment kube-prometheus-stack-grafana -n monitoring --replicas=3
```

Database corruption occurred again within seconds:
```
level=error msg="failed to save dashboard" error="database disk image is malformed"
```

Confirmed: SQLite + NFS + multiple writers = database corruption.

_____________________________________________________________________

[Final Root Cause]
Grafana was configured with 3 replicas using NFS storage (nfs-retain,
ReadWriteMany) with SQLite as the embedded database. SQLite uses file-level
locking that doesn't work reliably over NFS. Multiple Grafana pods writing
concurrently to `grafana.db` caused corruption, preventing all dashboard
provisioning.

_____________________________________________________________________

[Final Solution]

Changed Grafana replicas from 3 to 1 in helm-release.yaml:
```yaml
grafana:
  replicas: 1  # SQLite cannot handle multiple writers on NFS
```

Why not external database: MariaDB is dedicated to WordPress, adding another
database adds complexity and a SPOF. Single Grafana replica is acceptable —
monitoring is not mission-critical in this environment.

Deployed via Flux:
```
flux reconcile kustomization flux-system --with-source
flux reconcile kustomization infrastructure
flux reconcile kustomization apps
flux get kustomization
# All showing True/Ready

flux resume helmrelease kube-prometheus-stack -n monitoring
# ✔ HelmRelease kube-prometheus-stack reconciliation completed
# ✔ applied revision 82.18.0
```

Important: always wait for all kustomizations to reconcile BEFORE resuming the
HelmRelease. This ensures Flux has the new config (1 replica) and won't reconcile
with old values (3 replicas).

Verified: Yes — single Grafana replica running, all 27 dashboards loaded, no
corruption.

_____________________________________________________________________

[Risk Level] MEDIUM

Single Grafana replica means monitoring has no redundancy. Acceptable tradeoff
given SQLite limitation and environment scope.

_____________________________________________________________________

[References]
- TS-K8S-036 — Grafana anti-affinity rollout stuck (related Grafana scaling issue)
- kubernetes/dev/deployments/apps/monitoring/helm-release.yaml — Grafana config
