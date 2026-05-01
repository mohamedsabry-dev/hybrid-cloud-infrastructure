# Disaster Recovery Test Results

Platform-wide chaos test plans and results across k8s, Vault, etcd, NFS, Nginx, and IPA — what I broke intentionally and what I learned from it. Test-driven content, not runbooks.

> **Proxmox host-layer runbooks** (UPS monitor, thermal monitor, USB-Ethernet adapter replacement, full Proxmox reinstall from backup) live in [`../proxmox/disaster_recovery/`](../proxmox/disaster_recovery/). That folder is prevention + procedures for the hypervisor layer; this folder is testing + results for everything above it.

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
| [etcd-backup-s3-validation](etcd-backup-s3-validation.md) | Backup | PASS | Backup + S3 download + integrity verified |
| [etcd-single-node-recovery](etcd-single-node-recovery.md) | etcd | PASS | Quorum maintained, cluster sync recovery |
| [master-2of3-down](master-2of3-down.md) | Control Plane | PASS | CoreDNS is the hidden SPOF, not etcd |
| [worker-2of3-down](worker-2of3-down.md) | Compute | PASS | NoExecute taint bug, remediation auto-recovery |
| [app-pod-kill-wordpress-mariadb-injector](app-pod-kill-wordpress-mariadb-injector.md) | Application | PASS | Vault injector race condition → 2 replicas fix |
| [app-upload-during-outage](app-upload-during-outage.md) | Application | PASS | InnoDB rollback works, wpdb rejects at connection init |
| [app-ingress-nginx-failover](app-ingress-nginx-failover.md) | Network | PASS | Lua backend routing, endpoint removal on node loss |
| [network-external-nginx-failure](network-external-nginx-failure.md) | Network | PASS | LXC SPOF confirmed, Lambda auto-recovery planned |
| [network-ipa-dns-outage](network-ipa-dns-outage.md) | DNS | PASS | FreeIPA is DNS SPOF, 4 fixes applied |
| [storage-full-nas-shutdown](storage-full-nas-shutdown.md) | Storage | PASS | Soft vs hard mount validated, probe design correct |
| [storage-single-worker-nfs-down](storage-single-worker-nfs-down.md) | Storage | PASS | Readiness probe fix + Grafana HA fix |
| [vault-single-node-down](vault-single-node-down.md) | Vault | PASS | Real incident + deliberate test validated HA |
| [vault-raft-quorum-loss](vault-raft-quorum-loss.md) | Vault | PASS | Raft redirect behavior, new pods blocked |
| [vault-aws-kms-credential-loss](vault-aws-kms-credential-loss.md) | Vault | PASS | No credentials = hard failure, not sealed |
| [scheduler-failure-full-kill](scheduler-failure-full-kill.md) | Control Plane | PASS | Quietest failure in k8s — silent Pending, no events, no logs |

---

## Key Fixes Applied During Testing

| Fix | Source Test | Issue |
|-----|------------|-------|
| vault-agent-injector 2 replicas | app-pod-kill | Race condition on simultaneous restart |
| WordPress NFS readiness probe | storage-single-worker-nfs | Traffic routed to broken NFS pod |
| Grafana 3 replicas + RWX | storage-single-worker-nfs | Single replica SPOF |
| CoreDNS hosts plugin | network-ipa-dns | Pods can't resolve vault.lab.local during IPA outage |
| Node DNS fallback (8.8.8.8) | network-ipa-dns | External DNS dead when IPA down |
| Ansible KnownHostsCommand=none | network-ipa-dns | 34s → 3s during IPA outage |
| Remediation VM status check | worker-2of3-down | Couldn't handle stopped VMs |
| Event Exporter deployed | scheduler-failure-full-kill | kubectl events invisible from Grafana — 6th monitoring source |

---

## Known SPOFs (Accepted)

- FreeIPA (single instance)
- NAS / NFS storage (single instance)
- External NGINX (single LXC)
- MariaDB (single instance)
- VPN Tunnel
- Router / Switch / AP
