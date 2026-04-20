# Kubernetes Troubleshooting Cases

This directory contains documented troubleshooting cases for our Kubernetes infrastructure. Each case follows a standardized 9-point template for consistency and completeness.

---

## Template Structure

Each case document follows this format:

| Section | Description |
|---------|-------------|
| **1. Context** | System, environment, related components, discovery context |
| **2. Issue** | Symptom, error messages, impact |
| **3. Analysis** | Investigation steps with commands and outputs |
| **4. Root Cause** | Detailed explanation of why the issue occurred |
| **5. Solution** | Fix steps, files changed, prevention measures |
| **6. Solution Risk** | Risk level, potential impact of the fix |
| **7. Impact After Fix** | Observed results after applying the solution |
| **8. Notes** | Lessons learned, commands reference, related files |
| **9. Workaround** | Temporary fixes if permanent solution isn't immediately available |

**Header Format:** `# TS-K8S-XXX | YYYY-MM-DD | STATUS`

---

## Cases Index (Chronological)

| # | Date | Status | Title | Category |
|---|------|--------|-------|----------|
| [001](1-k8s-pod-eviction-race-condition-router-outage.md) | 2026-03-25 | RESOLVED | Pod Eviction Race Condition (Router Outage) | Scheduling |
| [002](2-calico-bgp-wrong-interface-multi-nic.md) | 2026-03-28 | RESOLVED | Calico BGP Wrong Interface (Multi-NIC) | Networking |
| [003](3-nfs-hard-mount-pod-unresponsiveness.md) | 2026-03-31 | RESOLVED | NFS Hard Mount Pod Unresponsiveness | Storage |
| [004](4-nfs-pv-reclaimpolicy-delete-failed-no-provisioner.md) | 2026-04-01 | RESOLVED | NFS PV ReclaimPolicy Delete Failed | Storage |
| [005](5-nfs-csi-storageclass-invalid-parameter-flux-stuck.md) | 2026-04-01 | RESOLVED | NFS CSI StorageClass Invalid Parameter + Flux Stuck | Storage / GitOps |
| [006](6-nfs-storage-complete-guide-static-to-dynamic.md) | 2026-04-02 | RESOLVED | NFS Storage Complete Guide (Static to Dynamic) | Storage |
| [007](7-mariadb-innodb-nfs-table-creation-failure.md) | 2026-04-02 | RESOLVED | MariaDB InnoDB NFS Table Creation Failure | Database / Storage |
| [008](8-k8s-dev-memory-overcommit-strategy.md) | 2026-04-03 | RESOLVED | K8s Dev Memory Over-Commitment Strategy | Resources |
| [009](9-k8s-scheduler-limitations-and-advanced-scheduling.md) | 2026-04-04 | IN PROGRESS | Kubernetes Scheduler Limitations | Scheduling |
| [010](10-wordpress-admin-password-hash-reset.md) | 2026-04-04 | MONITORING | WordPress Admin Password Hash Reset | Application |
| [011](11-wordpress-plugin-version-incompatibility-blank-page.md) | 2026-04-04 | RESOLVED | WordPress Plugin Version Incompatibility | Application |
| [012](12-flux-kustomization-crd-dependency-failure.md) | 2026-04-05 | RESOLVED | Flux Kustomization CRD Dependency Failure | GitOps |
| [013](13-k8s-master-node-resource-exhaustion.md) | 2026-04-05 | RESOLVED | K8s Master Node Resource Exhaustion | Resources |
| [014](14-vault-k8s-auth-service-account-not-authorized.md) | 2026-04-05 | RESOLVED | Vault K8s Auth Service Account Not Authorized | Security |
| [015](15-csi-nfs-restart-stale-mount-mariadb-crash.md) | 2026-04-06 | RESOLVED | CSI NFS Restart Stale Mount (MariaDB Crash) | Storage / Database |
| [016](16-pod-priority-classes-dr-readiness.md) | 2026-04-06 | RESOLVED | Pod Priority Classes (DR Readiness) | Scheduling |
| [017](17-vault-injection-system-namespace-denied.md) | 2026-04-07 | RESOLVED | Vault Injection System Namespace Denied | Security |
| [018](18-csi-nfs-controller-cannot-provision-pvc-network-isolation.md) | 2026-04-08 | RESOLVED | CSI NFS Controller Network Isolation | Storage / Networking |
| [019](19-flux-kustomization-restructure-cascade-failure.md) | 2026-04-09 | RESOLVED | Flux Kustomization Restructure Cascade Failure | GitOps |
| [020](20-grafana-loki-version-incompatibility.md) | 2026-04-10 | RESOLVED | Grafana + Loki Version Incompatibility | Monitoring |
| [021](21-remediation-pod-stopped-vm-api-error.md) | 2026-04-11 | RESOLVED | Remediation Pod Cannot Reboot Stopped VM | Self-Healing |
| [022](22-worker-node-failure-cascading-pod-failures.md) | 2026-04-11 | RESOLVED | Worker Node Failure Cascading Pod Failures | HA / Recovery |
| [023](23-kustomization-resource-not-removed.md) | 2026-04-11 | RESOLVED | Kustomization Resource Not Removed | GitOps |
| [024](24-vault-cluster-resilience-2-node-quorum.md) | 2026-04-11 | RESOLVED | Vault Cluster 2-Node Quorum Resilience | Security / HA |
| [025](25-promtail-vault-namespace-logs.md) | 2026-04-11 | SUSPENDED | Promtail Vault Namespace Logs | Monitoring |
| [026](26-released-pvs-cleanup.md) | 2026-04-13 | RESOLVED | Released PVs Cleanup (Orphaned Storage) | Storage |
| [027](27-wordpress-php-upload-limits.md) | 2026-04-13 | RESOLVED | WordPress PHP Upload Limits | Application |
| [028](28-nginx-proxy-body-size-413-error.md) | 2026-04-13 | RESOLVED | External Nginx Proxy 413 Body Size Error | Networking / Proxy |
| [029](29-wordpress-readiness-probe-nfs-detection.md) | 2026-04-13 | RESOLVED | WordPress Readiness Probe NFS Detection | Storage / Application |
| [030](30-worker3-memory-exhaustion-vm-crash.md) | 2026-04-14 | RESOLVED | Worker3 Memory Exhaustion VM Crash | Resources / HA |
| [031](31-wordpress-antiaffinity-scheduling.md) | 2026-04-15 | RESOLVED | WordPress Anti-Affinity Scheduling | Scheduling |
| [032](32-dr-2worker-failure-planning.md) | 2026-04-15 | IN PROGRESS | DR 2-Worker Failure Planning | HA / DR |
| [033](33-vault-agent-dns-failure-new-pod-blocking.md) | 2026-04-16 | RESOLVED | Vault Agent DNS Failure New Pod Blocking | Security / DNS |
| [034](34-wordpress-external-dns-slowness.md) | 2026-04-16 | RESOLVED | WordPress External DNS Slowness | Networking / DNS |
| [035](35-pod-restart-investigation-ipa-down.md) | 2026-04-15 | RESOLVED | Pod Restart Investigation (IPA Down) | Identity / HA |
| [036a](36-wordpress-liveness-probe-nfs-resilience.md) | 2026-04-17 | DOCUMENTED | WordPress Liveness Probe NFS Resilience | Storage / Application |
| [036b](36-grafana-antiaffinity-rollout-stuck.md) | 2026-04-18 | RESOLVED | Grafana Anti-Affinity Rollout Stuck | Scheduling |
| [037](37-grafana-dashboards-missing-sqlite-corruption.md) | 2026-04-18 | RESOLVED | Grafana Dashboards Missing (SQLite Corruption) | Monitoring |
| [038](38-qemu-guest-agent-cpu-loop.md) | 2026-04-17 | OPEN | QEMU Guest Agent CPU Busy Loop | Platform |
| [039](39-kube-system-targetdown-false-positives.md) | 2026-04-18 | SUSPENDED | kube-system TargetDown False Positives | Monitoring |
| [040](40-hpa-memory-scaling-behavior.md) | 2026-04-18 | RESOLVED | HPA Memory-Based Scaling Behavior | Scheduling |
| [041](41-prometheusrule-not-picked-up.md) | 2026-04-18 | RESOLVED | PrometheusRule Not Picked Up | Monitoring |
| [042](42-flux-retry-storm-cluster-outage.md) | 2026-04-18 | RESOLVED | Flux Retry Storm Cluster-Wide Outage (P1) | GitOps / HA |
| [043](43-noexecute-taint-not-applied.md) | 2026-04-18 | RESOLVED | NoExecute Taint Not Applied to Unreachable Nodes | Scheduling |
| [044](44-coredns-ha-masters.md) | 2026-04-18 | RESOLVED | CoreDNS Not HA — Should Run on Masters | DNS / HA |
| [045](45-csi-nfs-controller-port-conflict.md) | 2026-04-18 | RESOLVED | CSI NFS Controller Port Conflict (Same Node) | Storage |
| [046](46-kustomization-stale-resource-reference.md) | 2026-04-20 | RESOLVED | Kustomization Stale Resource Reference | GitOps |
| [047](47-csi-nfs-podlabels-silent-accept.md) | 2026-04-20 | RESOLVED | CSI NFS podLabels Silent Accept + Near-Miss | Helm / Storage |
| [048](48-prometheus-pvc-nfsv4-version-mismatch.md) | 2026-04-20 | RESOLVED | Prometheus PVC NFSv4 Version Mismatch | Storage |

**Total: 49 cases** — 43 Resolved, 2 In Progress, 1 Monitoring, 1 Suspended, 1 Documented, 1 Open

---

## Cases by Category

### Storage (NFS / CSI) — 12 cases
- [003](3-nfs-hard-mount-pod-unresponsiveness.md) - NFS Hard Mount Pod Unresponsiveness
- [004](4-nfs-pv-reclaimpolicy-delete-failed-no-provisioner.md) - NFS PV ReclaimPolicy Delete Failed
- [005](5-nfs-csi-storageclass-invalid-parameter-flux-stuck.md) - NFS CSI StorageClass Invalid Parameter
- [006](6-nfs-storage-complete-guide-static-to-dynamic.md) - **Complete NFS Storage Guide**
- [007](7-mariadb-innodb-nfs-table-creation-failure.md) - MariaDB InnoDB NFS Table Creation Failure
- [015](15-csi-nfs-restart-stale-mount-mariadb-crash.md) - CSI NFS Restart Stale Mount
- [018](18-csi-nfs-controller-cannot-provision-pvc-network-isolation.md) - CSI NFS Controller Network Isolation
- [026](26-released-pvs-cleanup.md) - Released PVs Cleanup (Orphaned Storage)
- [029](29-wordpress-readiness-probe-nfs-detection.md) - WordPress Readiness Probe NFS Detection
- [036a](36-wordpress-liveness-probe-nfs-resilience.md) - WordPress Liveness Probe NFS Resilience
- [045](45-csi-nfs-controller-port-conflict.md) - CSI NFS Controller Port Conflict (Same Node)
- [048](48-prometheus-pvc-nfsv4-version-mismatch.md) - Prometheus PVC NFSv4 Version Mismatch

### GitOps (Flux) — 6 cases
- [005](5-nfs-csi-storageclass-invalid-parameter-flux-stuck.md) - Flux Stuck on Old Revision
- [012](12-flux-kustomization-crd-dependency-failure.md) - Flux CRD Dependency Failure
- [019](19-flux-kustomization-restructure-cascade-failure.md) - Flux Restructure Cascade Failure
- [023](23-kustomization-resource-not-removed.md) - Kustomization Resource Not Removed
- [042](42-flux-retry-storm-cluster-outage.md) - Flux Retry Storm Cluster-Wide Outage (P1)
- [046](46-kustomization-stale-resource-reference.md) - Kustomization Stale Resource Reference

### Scheduling / Resources — 10 cases
- [001](1-k8s-pod-eviction-race-condition-router-outage.md) - Pod Eviction Race Condition
- [008](8-k8s-dev-memory-overcommit-strategy.md) - Memory Over-Commitment Strategy
- [009](9-k8s-scheduler-limitations-and-advanced-scheduling.md) - Scheduler Limitations
- [013](13-k8s-master-node-resource-exhaustion.md) - Master Node Resource Exhaustion
- [016](16-pod-priority-classes-dr-readiness.md) - Pod Priority Classes
- [030](30-worker3-memory-exhaustion-vm-crash.md) - Worker3 Memory Exhaustion VM Crash
- [031](31-wordpress-antiaffinity-scheduling.md) - WordPress Anti-Affinity Scheduling
- [036b](36-grafana-antiaffinity-rollout-stuck.md) - Grafana Anti-Affinity Rollout Stuck
- [040](40-hpa-memory-scaling-behavior.md) - HPA Memory-Based Scaling Behavior
- [043](43-noexecute-taint-not-applied.md) - NoExecute Taint Not Applied to Unreachable Nodes

### Security (Vault) — 4 cases
- [014](14-vault-k8s-auth-service-account-not-authorized.md) - Vault K8s Auth Not Authorized
- [017](17-vault-injection-system-namespace-denied.md) - Vault Injection System Namespace Denied
- [024](24-vault-cluster-resilience-2-node-quorum.md) - Vault Cluster 2-Node Quorum Resilience
- [033](33-vault-agent-dns-failure-new-pod-blocking.md) - Vault Agent DNS Failure New Pod Blocking

### Networking / DNS — 5 cases
- [002](2-calico-bgp-wrong-interface-multi-nic.md) - Calico BGP Wrong Interface
- [018](18-csi-nfs-controller-cannot-provision-pvc-network-isolation.md) - Network Isolation Issue
- [028](28-nginx-proxy-body-size-413-error.md) - External Nginx Proxy 413 Body Size Error
- [034](34-wordpress-external-dns-slowness.md) - WordPress External DNS Slowness
- [044](44-coredns-ha-masters.md) - CoreDNS Not HA — Should Run on Masters

### Applications — 5 cases
- [010](10-wordpress-admin-password-hash-reset.md) - WordPress Password Reset
- [011](11-wordpress-plugin-version-incompatibility-blank-page.md) - WordPress Plugin Incompatibility
- [020](20-grafana-loki-version-incompatibility.md) - Grafana + Loki Version Incompatibility
- [027](27-wordpress-php-upload-limits.md) - WordPress PHP Upload Limits
- [029](29-wordpress-readiness-probe-nfs-detection.md) - WordPress Readiness Probe NFS Detection

### Monitoring — 5 cases
- [020](20-grafana-loki-version-incompatibility.md) - Grafana + Loki Version Incompatibility
- [025](25-promtail-vault-namespace-logs.md) - Promtail Vault Namespace Logs (SUSPENDED)
- [037](37-grafana-dashboards-missing-sqlite-corruption.md) - Grafana Dashboards Missing (SQLite Corruption)
- [039](39-kube-system-targetdown-false-positives.md) - kube-system TargetDown False Positives
- [041](41-prometheusrule-not-picked-up.md) - PrometheusRule Not Picked Up

### Database — 2 cases
- [007](7-mariadb-innodb-nfs-table-creation-failure.md) - MariaDB InnoDB on NFS
- [015](15-csi-nfs-restart-stale-mount-mariadb-crash.md) - MariaDB Crash from Stale Mount

### Self-Healing / HA / DR — 3 cases
- [021](21-remediation-pod-stopped-vm-api-error.md) - Remediation Pod API Error (Stopped VM)
- [022](22-worker-node-failure-cascading-pod-failures.md) - Worker Node Failure Cascade Recovery
- [032](32-dr-2worker-failure-planning.md) - DR 2-Worker Failure Planning

### Identity — 1 case
- [035](35-pod-restart-investigation-ipa-down.md) - Pod Restart Investigation (IPA Down)

### Platform — 1 case
- [038](38-qemu-guest-agent-cpu-loop.md) - QEMU Guest Agent CPU Busy Loop

### Helm — 1 case
- [047](47-csi-nfs-podlabels-silent-accept.md) - CSI NFS podLabels Silent Accept + Near-Miss

---

## Quick Reference

### Status Definitions
| Status | Meaning |
|--------|---------|
| RESOLVED | Issue fixed, root cause identified, prevention in place |
| IN PROGRESS | Investigation or fix ongoing |
| MONITORING | Workaround applied, monitoring for recurrence |
| SUSPENDED | Partially investigated, paused for later |
| DOCUMENTED | Design/behavior documented, no fix needed |
| OPEN | Issue identified, not yet resolved |

### Common Commands

```bash
# Check pod status
kubectl get pods -A -o wide

# Check node resources
kubectl describe nodes | grep -E "(Name:|memory|cpu)"

# Check PVC status
kubectl get pvc -A

# Check Flux status
flux get kustomizations
flux get helmreleases -A

# Check CSI driver
kubectl get pods -n kube-system | grep csi

# Check Vault status
kubectl get pods -n vault
kubectl logs -n vault vault-agent-injector-xxx
```

---

## Environment

| Component | Version |
|-----------|---------|
| Kubernetes | v1.31.x (kubeadm) |
| CNI | Calico v3.27.x |
| Storage | NFS CSI Driver |
| GitOps | Flux v2 |
| Secrets | HashiCorp Vault |
| Monitoring | Prometheus + Grafana + Loki |

**Clusters:**
- `k8s-dev` - Development/testing
- `k8s-prod` - Production

---

## Contributing

When adding a new case:
1. Use the next sequential number based on date
2. Follow the 9-point template structure
3. Include all commands and outputs from investigation
4. Update this README with the new case
5. Cross-reference related cases where applicable
