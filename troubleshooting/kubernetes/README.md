# Kubernetes Troubleshooting Cases

42 cases + 8 reference guides in [reference/](reference/)

| # | Date | Status | Title |
|---|------|--------|-------|
| [001](1-k8s-pod-eviction-race-condition-router-outage.md) | 2026-03-25 | RESOLVED | Pod Eviction Race Condition (Router Outage) |
| [002](2-calico-bgp-wrong-interface-multi-nic.md) | 2026-03-28 | RESOLVED | Calico BGP Wrong Interface (Multi-NIC) |
| [003](3-nfs-hard-mount-pod-unresponsiveness.md) | 2026-03-31 | RESOLVED | NFS Hard Mount Pod Unresponsiveness |
| [004](4-nfs-pv-reclaimpolicy-delete-failed-no-provisioner.md) | 2026-04-01 | RESOLVED | NFS PV ReclaimPolicy Delete Failed |
| [005](5-nfs-csi-storageclass-invalid-parameter-flux-stuck.md) | 2026-04-01 | RESOLVED | NFS CSI StorageClass Invalid Parameter + Flux Stuck |
| [007](7-mariadb-innodb-nfs-table-creation-failure.md) | 2026-04-02 | RESOLVED | MariaDB InnoDB NFS Table Creation Failure |
| [010](10-wordpress-admin-password-hash-reset.md) | 2026-04-04 | TEMP CLOSED | WordPress Admin Password Hash Reset |
| [011](11-wordpress-plugin-version-incompatibility-blank-page.md) | 2026-04-04 | RESOLVED | WordPress Plugin Version Incompatibility |
| [012](12-flux-kustomization-crd-dependency-failure.md) | 2026-04-05 | RESOLVED | Flux Kustomization CRD Dependency Failure |
| [013](13-k8s-master-node-resource-exhaustion.md) | 2026-04-05 | RESOLVED | Master Node Resource Exhaustion |
| [014](14-vault-k8s-auth-service-account-not-authorized.md) | 2026-04-05 | RESOLVED | Vault K8s Auth Service Account Not Authorized |
| [015](15-csi-nfs-restart-stale-mount-mariadb-crash.md) | 2026-04-06 | RESOLVED | CSI NFS Restart Stale Mount (MariaDB Crash) |
| [016](16-pod-priority-classes-dr-readiness.md) | 2026-04-06 | RESOLVED | Pod Priority Classes (DR Readiness) |
| [017](17-vault-injection-system-namespace-denied.md) | 2026-04-07 | RESOLVED | Vault Injection System Namespace Denied |
| [018](18-csi-nfs-controller-cannot-provision-pvc-network-isolation.md) | 2026-04-08 | RESOLVED | CSI NFS Controller Network Isolation |
| [019](19-flux-kustomization-restructure-cascade-failure.md) | 2026-04-09 | RESOLVED | Flux Kustomization Restructure Cascade Failure |
| [020](20-grafana-loki-version-incompatibility.md) | 2026-04-10 | RESOLVED | Grafana + Loki Version Incompatibility |
| [021](21-remediation-pod-stopped-vm-api-error.md) | 2026-04-11 | RESOLVED | Remediation Pod Cannot Reboot Stopped VM |
| [022](22-worker-node-failure-cascading-pod-failures.md) | 2026-04-11 | RESOLVED | Worker Node Failure Cascading Pod Failures |
| [023](23-kustomization-resource-not-removed.md) | 2026-04-11 | RESOLVED | Kustomization Resource Not Removed |
| [025](25-promtail-vault-namespace-logs.md) | 2026-04-11 | SUSPENDED | Promtail Vault Namespace Logs |
| [026](26-released-pvs-cleanup.md) | 2026-04-13 | RESOLVED | Released PVs Cleanup (Orphaned Storage) |
| [027](27-wordpress-php-upload-limits.md) | 2026-04-13 | RESOLVED | WordPress PHP Upload Limits |
| [028](28-nginx-proxy-body-size-413-error.md) | 2026-04-13 | RESOLVED | External Nginx Proxy 413 Body Size Error |
| [029](29-wordpress-readiness-probe-nfs-detection.md) | 2026-04-13 | RESOLVED | WordPress Readiness Probe NFS Detection |
| [030](30-worker3-memory-exhaustion-vm-crash.md) | 2026-04-14 | RESOLVED | Worker3 Memory Exhaustion VM Crash |
| [033](33-vault-agent-dns-failure-new-pod-blocking.md) | 2026-04-16 | RESOLVED | Vault Agent DNS Failure New Pod Blocking |
| [034](34-wordpress-external-dns-slowness.md) | 2026-04-16 | RESOLVED | WordPress External DNS Slowness |
| [036](36-grafana-antiaffinity-rollout-stuck.md) | 2026-04-18 | RESOLVED | Grafana Anti-Affinity Rollout Stuck |
| [037](37-grafana-dashboards-missing-sqlite-corruption.md) | 2026-04-18 | RESOLVED | Grafana Dashboards Missing (SQLite Corruption) |
| [038](38-qemu-guest-agent-cpu-loop.md) | 2026-04-17 | TRIGGER NOT IDENTIFIED | QEMU Guest Agent CPU Busy Loop |
| [039](39-kube-system-targetdown-false-positives.md) | 2026-04-18 | SUSPENDED | kube-system TargetDown False Positives |
| [040](40-hpa-memory-scaling-behavior.md) | 2026-04-18 | RESOLVED | HPA Memory-Based Scaling Behavior |
| [041](41-prometheusrule-not-picked-up.md) | 2026-04-18 | RESOLVED | PrometheusRule Not Picked Up |
| [042](42-flux-retry-storm-cluster-outage.md) | 2026-04-18 | RESOLVED | Flux Retry Storm Cluster-Wide Outage |
| [043](43-noexecute-taint-not-applied.md) | 2026-04-18 | RESOLVED | NoExecute Taint Not Applied to Unreachable Nodes |
| [044](44-coredns-ha-masters.md) | 2026-04-18 | RESOLVED | CoreDNS Not HA — Should Run on Masters |
| [045](45-csi-nfs-controller-port-conflict.md) | 2026-04-18 | RESOLVED | CSI NFS Controller Port Conflict (Same Node) |
| [046](46-kustomization-stale-resource-reference.md) | 2026-04-20 | RESOLVED | Kustomization Stale Resource Reference |
| [047](47-csi-nfs-podlabels-silent-accept.md) | 2026-04-20 | RESOLVED | CSI NFS podLabels Silent Accept + Near-Miss |
| [048](48-prometheus-pvc-nfsv4-version-mismatch.md) | 2026-04-20 | RESOLVED | Prometheus PVC NFSv4 Version Mismatch |
| [049](49-git-history-rewrite-flux-prune-cascade.md) | 2026-04-23 | RESOLVED | Git History Rewrite → Flux Prune Cascade (CoreDNS Lost) |
