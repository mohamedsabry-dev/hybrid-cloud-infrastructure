# Disaster Recovery Test Results

---

## Real Incidents Before DR Testing

Before the planned DR test phase even began, real production incidents occurred that validated (and exposed gaps in) the architecture:

**Incident 1: Power Outage (April 9, 2026)**
- Triggered 5+ troubleshooting cases
- Exposed UPS monitor cron misconfiguration, VM autostart timing issues, Flux cascade failures
- Related cases: TS-PVE-012, TS-PVE-013, TS-K8S-018, TS-K8S-019

**Incident 2: Prod Worker VM Crash (April 11, 2026)**
- Worker VM crashed ~1 minute after boot, unknown cause
- Exposed remediation pod bug (can't reboot stopped VMs), vault-injector race condition
- Led to architecture improvements: remediation status check, vault-injector 2 replicas
- Related cases: TS-PVE-014, TS-K8S-021, TS-K8S-022, TS-K8S-023

**Incident 3: Dev Proxmox Crash During Backup (April 11, 2026)**
- Proxmox host crashed silently during vzdump, unknown cause
- Vault node (vault3) went down, validated 2-node quorum resilience
- Exposed stale Raft data recovery procedure
- Related cases: TS-PVE-015, TS-VLT-005, TS-K8S-024

---

## Completed Tests

| Test | Domain | Result | Key Finding |
|------|--------|--------|-------------|
| [proxmox-vzdump-backup](proxmox-vzdump-backup.md) | Backup | PASS | Live backups non-disruptive to pods |
| [etcd-backup-s3](etcd-backup-s3.md) | Backup | PASS | Manual + automated S3 backup working |
| [etcd-s3-backup-validation](etcd-s3-backup-validation.md) | Backup | PASS | Snapshot integrity verified |
| [etcd-single-node-failure](etcd-single-node-failure.md) | etcd | PASS | Quorum maintained, auto-recovery works |
| [pod-kill-tests](pod-kill-tests.md) | Compute | PARTIAL | Race condition found → 2 replicas fix |
| [mid-upload-scale-zero](mid-upload-scale-zero.md) | Compute | PASS | InnoDB rollback works, no corruption |
| [single-worker-nfs-down](single-worker-nfs-down.md) | Storage | PASS | NFS readiness probe fix applied |
| [vault-single-node-down](vault-single-node-down.md) | Vault | Reference | Real incident validated HA |
| [vault-quorum-loss](vault-quorum-loss.md) | Vault | PASS | 2/3 down recovery documented |
| [vault-aws-kms-dependency](vault-aws-kms-dependency.md) | Vault | PASS | Auto-unseal failure handling verified |

---

## Pending Tests

| Test | Domain | Priority | Notes |
|------|--------|----------|-------|
| [tmp-full-nas-shutdown](tmp-full-nas-shutdown.md) | Storage | CRITICAL | Most realistic disaster scenario |
| [tmp-etcd-full-cluster-restore](tmp-etcd-full-cluster-restore.md) | etcd | CRITICAL | Validate S3 backup restore path |
| [tmp-external-nginx-down](tmp-external-nginx-down.md) | Network | CRITICAL | SPOF confirmation |
| [tmp-ingress-nginx-kill](tmp-ingress-nginx-kill.md) | Network | HIGH | Combine with external nginx test |
| [tmp-partial-worker-loss](tmp-partial-worker-loss.md) | Compute | HIGH | 2/3 workers down + remediation |
| [tmp-partial-master-loss](tmp-partial-master-loss.md) | Control Plane | HIGH | 2/3 masters, API server behavior |
| [tmp-ipa-domain-down](tmp-ipa-domain-down.md) | Identity | HIGH | Trace DNS/auth dependencies |
| [tmp-pod-creation-during-nfs-outage](tmp-pod-creation-during-nfs-outage.md) | Storage | MEDIUM | Run during NAS shutdown test |
| [tmp-graceful-power-down](tmp-graceful-power-down.md) | Power | MEDIUM | Document shutdown order |
| [tmp-recovery-boot-sequence](tmp-recovery-boot-sequence.md) | Power | MEDIUM | Document startup order |

---

## Key Fixes Applied During Testing

| Fix | File | Issue |
|-----|------|-------|
| vault-agent-injector 2 replicas | helm-release.yaml | Race condition on simultaneous restart |
| WordPress NFS readiness probe | deployment.yaml | Traffic routed to broken NFS pod |
| Grafana 3 replicas + RWX | helm-release.yaml | Single replica SPOF |
| Remediation VM status check | configmap.yaml | Couldn't handle stopped VMs |

---

## Known SPOFs (Accepted)

- FreeIPA (single instance)
- NAS / NFS storage (single instance)
- External NGINX (single LXC)
- MariaDB (single instance)
- VPN Tunnel
- Router / Switch / AP
