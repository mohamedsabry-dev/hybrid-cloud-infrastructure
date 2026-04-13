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
| [025](25-promtail-vault-namespace-logs.md) | 2026-04-11 | PLACEHOLDER | Promtail Vault Namespace Logs | Monitoring |
| [026](26-released-pvs-cleanup.md) | 2026-04-13 | RESOLVED | Released PVs Cleanup (Orphaned Storage) | Storage |
| [027](27-wordpress-php-upload-limits.md) | 2026-04-13 | RESOLVED | WordPress PHP Upload Limits | Application |
| [028](28-nginx-proxy-body-size-413-error.md) | 2026-04-13 | RESOLVED | External Nginx Proxy 413 Body Size Error | Networking / Proxy |

---

## Cases by Category

### Storage (NFS / CSI)
- [003](3-nfs-hard-mount-pod-unresponsiveness.md) - NFS Hard Mount Pod Unresponsiveness
- [004](4-nfs-pv-reclaimpolicy-delete-failed-no-provisioner.md) - NFS PV ReclaimPolicy Delete Failed
- [005](5-nfs-csi-storageclass-invalid-parameter-flux-stuck.md) - NFS CSI StorageClass Invalid Parameter
- [006](6-nfs-storage-complete-guide-static-to-dynamic.md) - **Complete NFS Storage Guide**
- [007](7-mariadb-innodb-nfs-table-creation-failure.md) - MariaDB InnoDB NFS Table Creation Failure
- [015](15-csi-nfs-restart-stale-mount-mariadb-crash.md) - CSI NFS Restart Stale Mount
- [018](18-csi-nfs-controller-cannot-provision-pvc-network-isolation.md) - CSI NFS Controller Network Isolation
- [026](26-released-pvs-cleanup.md) - Released PVs Cleanup (Orphaned Storage)

### GitOps (Flux)
- [005](5-nfs-csi-storageclass-invalid-parameter-flux-stuck.md) - Flux Stuck on Old Revision
- [012](12-flux-kustomization-crd-dependency-failure.md) - Flux CRD Dependency Failure
- [019](19-flux-kustomization-restructure-cascade-failure.md) - Flux Restructure Cascade Failure

### Scheduling / Resources
- [001](1-k8s-pod-eviction-race-condition-router-outage.md) - Pod Eviction Race Condition
- [008](8-k8s-dev-memory-overcommit-strategy.md) - Memory Over-Commitment Strategy
- [009](9-k8s-scheduler-limitations-and-advanced-scheduling.md) - Scheduler Limitations
- [013](13-k8s-master-node-resource-exhaustion.md) - Master Node Resource Exhaustion
- [016](16-pod-priority-classes-dr-readiness.md) - Pod Priority Classes

### Security (Vault)
- [014](14-vault-k8s-auth-service-account-not-authorized.md) - Vault K8s Auth Not Authorized
- [017](17-vault-injection-system-namespace-denied.md) - Vault Injection System Namespace Denied

### Networking / Proxy
- [002](2-calico-bgp-wrong-interface-multi-nic.md) - Calico BGP Wrong Interface
- [018](18-csi-nfs-controller-cannot-provision-pvc-network-isolation.md) - Network Isolation Issue
- [028](28-nginx-proxy-body-size-413-error.md) - External Nginx Proxy 413 Body Size Error

### Applications
- [010](10-wordpress-admin-password-hash-reset.md) - WordPress Password Reset
- [011](11-wordpress-plugin-version-incompatibility-blank-page.md) - WordPress Plugin Incompatibility
- [020](20-grafana-loki-version-incompatibility.md) - Grafana + Loki Version Incompatibility
- [027](27-wordpress-php-upload-limits.md) - WordPress PHP Upload Limits

### Monitoring
- [020](20-grafana-loki-version-incompatibility.md) - Grafana + Loki Version Incompatibility
- [025](25-promtail-vault-namespace-logs.md) - Promtail Vault Namespace Logs (PLACEHOLDER)

### Database
- [007](7-mariadb-innodb-nfs-table-creation-failure.md) - MariaDB InnoDB on NFS
- [015](15-csi-nfs-restart-stale-mount-mariadb-crash.md) - MariaDB Crash from Stale Mount

### Self-Healing / HA
- [021](21-remediation-pod-stopped-vm-api-error.md) - Remediation Pod API Error (Stopped VM)
- [022](22-worker-node-failure-cascading-pod-failures.md) - Worker Node Failure Cascade Recovery
- [024](24-vault-cluster-resilience-2-node-quorum.md) - Vault Cluster 2-Node Quorum Resilience

### GitOps (Flux) - Additional
- [023](23-kustomization-resource-not-removed.md) - Kustomization Resource Not Removed

---

## Quick Reference

### Status Definitions
| Status | Meaning |
|--------|---------|
| RESOLVED | Issue fixed, root cause identified, prevention in place |
| IN PROGRESS | Investigation or fix ongoing |
| MONITORING | Workaround applied, monitoring for recurrence |
| PLACEHOLDER | Issue identified but not yet investigated |

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
