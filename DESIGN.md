# Design Decisions

Why the infrastructure is built the way it is. Current reasoning only — for evolution history, check troubleshooting cases and `archive-poc-v1/`.

---

## Why Hybrid

Pure cloud doesn't teach you hardware, networking, thermal management, or physical failure modes. Pure on-prem doesn't teach you cloud IAM, OIDC, or managed services. This project needs both because that's what real infrastructure looks like — and because the learning surface is wider when you own both sides of the tunnel.

AWS handles what it's good at: IAM/OIDC for CI/CD auth, KMS for Vault auto-unseal, S3 for off-site etcd backups, Route53 for private DNS. On-prem handles compute, identity, and the Kubernetes cluster — where the real operational learning happens.

## Why 2 Physical Servers

Dev mirrors prod at the same topology but smaller resources (24GB dev vs 64GB prod). Every change lands on dev first. The environments are completely isolated — separate VLANs, separate Proxmox hosts, separate AWS accounts and regions, separate git branches. The router blocks all cross-environment traffic at L3.

Two hosts also means two separate failure domains. If dev's NVMe dies, prod is untouched. Real hardware problems — thermal throttling during vzdump, USB-Ethernet adapter failures, IO storms from shared NVMe — only surface on physical machines. Nested VMs hide them.

## Tool Choices

I picked each tool for a specific reason, not because it's popular:

**Proxmox** — Open-source, CLI-native, has a Terraform provider (bpg/proxmox), doesn't need a vCenter eating 16GB of RAM. API is clean enough for the remediation pod to act on VMs directly.

**FreeIPA** — Linux-native identity (SSSD + Kerberos + LDAP) in one package. Single operational surface for DNS, authentication, sudo rules, and HBAC. Eliminates "which LDAP server handles what" confusion.

**Vault** — K8s Secrets are base64 (not encryption), live in etcd, and can't generate temporary AWS credentials. Vault does all three, plus LDAP auth against FreeIPA and full audit logging. The AWS Secrets Engine mints short-lived STS creds for etcd-backup — no long-lived AWS keys anywhere in the cluster.

**Flux** — Pull-based GitOps. The cluster pulls from Git, no CI system pushes into the cluster. CRD-native (HelmRelease, Kustomization as K8s objects). Lighter footprint than ArgoCD for a homelab.

**MikroTik** — RouterOS CLI is scriptable (`.rsc` config files live in the repo). Diagnostic tooling I can actually use: packet sniffer, per-interface stats, granular logs. The previous TP-Link ER605 had no useful CLI for debugging — three VPN/link incidents in a row proved I needed better visibility.

**WireGuard** — Simple config, one UDP port per tunnel, works through CGNAT with keepalive. IPsec is overbuilt for a 2-tunnel homelab.

**Single repo** — Everything lives in one repo because the components are tightly coupled. Terraform provisions VMs that Ansible configures that Kubernetes runs on that Flux reconciles from this same repo. Splitting would create cross-repo dependency chains with no benefit at this scale.

---

## Key Architectural Patterns

### Vault Injection — No Secrets in Git

Every app needing secrets uses the same pattern: pre-created ServiceAccount → Vault K8s auth role → `vault.hashicorp.com/agent-inject` annotations on the pod → Vault Agent sidecar renders secrets at startup. FreeIPA CA cert (vault-ca Secret) enables TLS trust. The pattern is identical for Grafana, MariaDB, WordPress, Alertmanager, remediation, and etcd-backup. Only the role name and secret path change.

For CronJobs (etcd-backup), the sidecar runs in init-container mode (`agent-pre-populate-only: true`) — secrets appear at startup, sidecar exits, job runs and dies. No persistent process for a 30-second backup job.

### Flux 2-Layer Split

Infrastructure (namespaces, storage classes, Vault injector, ingress-nginx, CoreDNS, metrics-server) deploys first. Apps (monitoring, WordPress, remediation, etcd-backup) deploy second with `dependsOn: infrastructure`.

Why the split: a single Kustomization had CRD race conditions (TS-K8S-012). HelmRelease applied before its CRD existed because Flux doesn't guarantee ordering within a single kustomize build. Splitting with `dependsOn` at the Flux layer solved it.

Infrastructure also has a health check on the Vault Agent Injector deployment. If injector isn't Ready, apps don't deploy — because almost every app pod has vault injection annotations. Without this gate, pods would silently start without secrets and crash.

### NFS Storage — 3 Classes, Same NAS

All persistent data lives on a Synology NAS accessible via VLAN 40 (L2-isolated, no router hop). Three StorageClasses serve different failure tolerance:

- **nfs-retain** (soft mount, 3s timeout) — Grafana, Prometheus, Loki, WordPress. Returns IO errors fast if NAS goes down. Apps decide how to handle failure.
- **nfs-database** (hard mount, 60s timeout) — MariaDB only. Hangs on NFS failure instead of returning errors. InnoDB can't handle silent IO errors mid-write — a soft mount error during a transaction can corrupt data.
- **nfs-delete** (soft mount) — Testing. PV deleted when PVC is removed.

All pinned to NFSv3 with `nolock` — the NFSv3 lock manager is flaky across VLANs, and NFS locking adds complexity with zero benefit for these workloads.

K8s workers have a dedicated second NIC on VLAN 40 for CSI-NFS access, bypassing the hypervisor in the NFS data path. Storage traffic never crosses the service VLANs.

### Master-Only Placement for Critical Services

CoreDNS, Vault Injector, Alertmanager, remediation pod, and etcd-backup all run on control-plane nodes with nodeSelector and master taint tolerations. The reasoning is simple: if all workers die, the platform should still function — DNS resolves, secrets inject, alerts fire, remediation reboots workers via Proxmox API.

This is the self-healing design in action. The remediation pod detects stopped workers, calls the Proxmox API to reboot/reset them, and workers rejoin the cluster automatically. If remediation ran on a worker, it'd die with the thing it's supposed to fix.

### Priority Class Hierarchy

Under memory pressure, pods die in this order:

1. testing (default, 0) — dies first
2. WordPress, metrics-server (app-standard, 500K)
3. MariaDB (database-critical, 1M)
4. Remediation, Alertmanager (self-healing-critical, 1M)
5. Flux, CoreDNS, ingress, CSI (system-cluster-critical, 2B) — dies last

The ordering is intentional: apps die before the database, the database dies before the self-healing system, and the self-healing system dies before the platform controllers.

### Remediation — 2-Phase Health Check

The remediation pod doesn't act on the first NotReady signal — that would trigger false reboots during IO storms, brief kubelet heartbeat misses, or backup-related CPU spikes (all of which actually happened on dev).

- **Phase 1** (every 5 min): Check all workers. Flag any NotReady nodes as suspects.
- **Phase 1.5** (wait 3 min): Re-check suspects. If a node recovered on its own, it was a false alarm. If still NotReady, it's confirmed unhealthy.
- **Phase 2**: Escalate — attempt 1 = ACPI reboot, attempt 2 = hard reset, attempt 3 = alert for manual intervention.

The 3-minute confirmation delay is dev-specific — the dev server's single NVMe with 13+ guests makes brief IO stalls common. Prod has better IO headroom, so it could run a shorter delay.

### GitHub Actions — OIDC, No Long-Lived AWS Keys

Every workflow authenticates to AWS via OIDC. GitHub mints a token, the workflow calls `sts:AssumeRole` with that token, and gets temporary credentials scoped to the specific role and environment. No AWS access keys stored as GitHub secrets — ever.

Branch-scoped trust: `dev` branch can only assume `GitHubActions-Infrastructure-dev`. Security-sensitive operations (IAM changes, KMS key management) require pushing to the `dev-security` branch, which assumes an elevated `GitHubActions-TerraformAdmin-dev` role. This separation means regular infrastructure pushes can't accidentally modify IAM.

Per-job workflow locks (repo variables set to `true`) let me skip individual jobs without disabling the entire workflow. The `always()` trick on dependent jobs prevents a locked upstream job from auto-skipping everything downstream — each job evaluates its own lock independently.

### Network — VLANs as Scaffolding

13 VLANs across management, storage, and service planes. Most can currently talk to each other — intra-environment ACLs are light. That's intentional.

VLANs are structure, not enforcement (yet). The IP address tells you what you're looking at: 10.0.62.x = dev Vault, 10.0.64.x = dev workers, 10.0.40.x = storage. Broadcast domain isolation prevents L2 noise. The VLAN plumbing is already in place for future tightening — "restrict vault to specific k8s workers" becomes a single MikroTik firewall rule, not a network restructure.

The one hard boundary: dev and prod never cross. Router blocks all traffic between VLAN ranges 50-55 and 60-65. This is non-negotiable regardless of how permissive intra-env rules are.

Storage VLAN 40 is L2-isolated on the switch — no routing, no router hop. NAS, Proxmox storage interfaces, and K8s worker second NICs communicate directly at L2.

---

## Trade-offs Accepted

These are known SPOFs I've chosen to live with, each with a documented mitigation path:

| SPOF | Mitigation | Path to HA |
|------|-----------|------------|
| FreeIPA (single instance) | CoreDNS hosts plugin for Vault/K8s VIPs, node DNS fallback to 8.8.8.8, ~15-min Proxmox restore | IPA replica server |
| NAS (single appliance) | Soft mounts fail fast, hard mount for DB only, vzdump backups live on NAS | Off-site replication |
| External Nginx (single LXC) | Triage: timeout vs refused identifies failure mode | Lambda auto-restart or keepalived VIP |
| MariaDB (single instance) | InnoDB crash recovery, hard NFS mount, StatefulSet handles node failure | Galera cluster |
| Grafana (single replica) | SQLite can't multi-write on NFS | External PostgreSQL DB |

Each has a clear upgrade path. I chose not to over-engineer for a lab where I'm the only user. The DR tests validated that these SPOFs fail gracefully — nothing silently corrupts, and recovery procedures are documented.

---

## What This Doesn't Have Yet

- **NetworkPolicy isolation** — VLANs segment at network layer, but no pod-level enforcement within the cluster
- **Custom PromQL/LogQL dashboards** — monitoring stack is deployed, custom queries aren't built yet
- **Lambda master recovery** — when the K8s API is down, the remediation pod can't act. Need an out-of-cluster recovery path
- **Node-level firewalls** — firewalld is disabled on all nodes. VLAN segmentation only
- **FreeIPA replica** — single instance accepted as SPOF
- **Dashboards-as-code** — Grafana dashboards are manual, persisted on NFS PVC

These are on the roadmap, not gaps I'm unaware of.
