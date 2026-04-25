# Apps — PROD Environment

Application-layer deployments managed by Flux. Everything here depends on the
infrastructure layer (`../infrastructure/`) being up first — namespaces,
storage classes, ingress controller, and the Vault Agent Injector all come
from there.

Every workload that touches secrets uses Vault Agent sidecar injection. No
hardcoded credentials anywhere in these manifests — SMTP passwords, DB
passwords, Proxmox tokens, AWS creds all come from Vault at pod startup.

---

## Directory layout

```
apps/
├── README.md                          # this file
├── kustomization.yaml                 # top-level — deploy order matters
├── monitoring/
│   ├── helm-release.yaml              # kube-prometheus-stack (Grafana + Prometheus)
│   ├── helm-repository.yaml           # prometheus-community Helm repo
│   ├── service-account.yaml           # grafana-sa (Vault auth identity)
│   ├── vault-ca-secret.yaml           # FreeIPA CA for Vault TLS
│   ├── custom-alerts.yaml             # 3 custom PrometheusRules
│   ├── setup-guide.txt                # first-deploy runbook
│   └── kustomization.yaml
├── alertmanager/
│   ├── statefulset.yaml               # standalone Alertmanager + Vault-injected SMTP config
│   ├── service.yaml                   # ClusterIP (9093 web + 9094 mesh)
│   ├── serviceaccount.yaml            # alertmanager-sa (Vault auth identity)
│   └── kustomization.yaml
├── logging/
│   ├── helm-release.yaml              # Loki (single-binary) + Promtail
│   ├── helm-repository.yaml           # Grafana Helm repo
│   └── kustomization.yaml
├── mariadb/
│   ├── statefulset.yaml               # MariaDB 10.11 + Vault-injected root/user passwords
│   ├── service.yaml                   # headless + ClusterIP + SA
│   ├── vault-ca-secret.yaml           # FreeIPA CA for Vault TLS
│   └── kustomization.yaml
├── wordpress/
│   ├── deployment.yaml                # WordPress 6.9 + Vault-injected DB password
│   ├── hpa.yaml                       # 2-4 replicas (CPU 70% / memory 80%)
│   ├── service.yaml                   # ClusterIP + Ingress + SA
│   ├── pvc.yaml                       # 30Gi RWX on nfs-retain
│   ├── php-config.yaml                # uploads.ini (100M upload, 256M memory)
│   ├── vault-ca-secret.yaml           # FreeIPA CA for Vault TLS
│   └── kustomization.yaml
├── remediation/
│   ├── deployment.yaml                # worker node self-healing (1 replica, master-only)
│   ├── configmap.yaml                 # Python remediation script
│   ├── priorityclass.yaml             # self-healing-critical (1M)
│   ├── remediation-auth-sa.yaml       # SA + read-only ClusterRole (nodes, pods)
│   ├── namespace.yaml                 # dedicated namespace
│   ├── vault-ca-secret.yaml           # FreeIPA CA for Vault TLS
│   ├── kustomization.yaml
│   ├── README.md                      # detailed ops docs
│   ├── DESIGN.md                      # design decisions + evolution
│   └── SETUP.md                       # first-deploy provisioning log
├── etcd-backup/
│   ├── cronjob.yaml                   # daily etcd snapshot → S3
│   ├── configmap.yaml                 # backup shell script
│   ├── namespace.yaml                 # dedicated namespace
│   ├── service-account.yaml           # etcd-backup-sa (Vault auth identity)
│   ├── vault-ca-secret.yaml           # FreeIPA CA for Vault TLS
│   └── kustomization.yaml
└── testing/
    ├── kustomization.yaml             # both tests commented out (reference only)
    ├── ingress-test/                  # bare ingress smoke test
    └── nginx-test/                    # NFS + Vault + ConfigMap integration test
```

## What each app does

| App | What | Namespace | Vault role | Storage |
|-----|------|-----------|------------|---------|
| **monitoring** | kube-prometheus-stack — Grafana, Prometheus, node-exporter. Scrapes 7 external infra nodes + all K8s workloads | `monitoring` | `grafana` | Grafana 10Gi + Prometheus 50Gi on `nfs-retain` |
| **alertmanager** | Standalone Alertmanager with SMTP email alerts via Gmail. Separated from the Helm stack so it gets its own Vault-injected config | `monitoring` | `alertmanager` | `emptyDir` (stateless) |
| **logging** | Loki (single-binary, 100Gi) + Promtail DaemonSet. 14-day retention, filesystem storage | `monitoring` | — | 100Gi on `nfs-retain` |
| **mariadb** | MariaDB 10.11, single instance. InnoDB fsync mode, slow query logging. Backs WordPress | `database` | `mariadb` | 50Gi on `nfs-database` (hard mount) |
| **wordpress** | WordPress 6.9 + Apache. HPA scales 2→4 replicas. Init container waits for MariaDB. Sticky sessions via ingress cookie | `apps` | `wordpress` | 30Gi RWX on `nfs-retain` |
| **remediation** | Python script that watches worker nodes and auto-remediates via Proxmox API (reboot → reset → restore from backup) | `remediation` | `remediation` | — |
| **etcd-backup** | Daily CronJob (20:30 Cairo time). Snapshots etcd, uploads to S3, cleans up local copies older than 7 days | `etcd-backup` | `etcd-backup` | hostPath `/var/lib/etcd-backup` |
| **testing** | Two reference test stacks (ingress smoke test + NFS/Vault integration test). Currently disabled | `testing` | `nginx` | 1Gi on `nfs-delete` |

## Vault integration pattern

Every app that needs secrets follows the same pattern:
1. A **ServiceAccount** in the app's namespace (e.g., `grafana-sa`, `mariadb-sa`)
2. A **vault-ca-secret** in the same namespace (FreeIPA CA cert for TLS verification)
3. Pod annotations that tell the Vault Agent Injector what role and secret path to use
4. The injected sidecar renders secrets to `/vault/secrets/` — the app's entrypoint sources them

The one exception is **etcd-backup**, which uses `agent-pre-populate-only: true` (init-container
mode, no persistent sidecar) because it's a batch Job that runs and exits.

Setup for each Vault role is done via `/opt/vault/scripts/vault-pod-setup.sh` on a Vault node —
documented in `monitoring/setup-guide.txt` and `remediation/SETUP.md`.

## Placement and HA

| App | Replicas | Placement | Anti-affinity |
|-----|----------|-----------|---------------|
| Grafana | 1 | any worker | preferred spread |
| Prometheus | 1 | any node | — |
| Alertmanager | 1 | control-plane only | — |
| Loki | 1 | any node | — |
| Promtail | DaemonSet | all nodes (including masters) | — |
| MariaDB | 1 | any node | — |
| WordPress | 2-4 (HPA) | any worker | preferred spread |
| Remediation | 1 | control-plane only | — |
| etcd-backup | CronJob | control-plane only (hostNetwork) | — |

Control-plane placement for Alertmanager, Remediation, and etcd-backup is intentional —
these need to keep running even when workers are down.

## Alerting flow

Prometheus evaluates alert rules (built-in + `custom-alerts.yaml`) → fires to the standalone
Alertmanager at `alertmanager.monitoring.svc:9093` → Alertmanager sends email via Gmail SMTP
(credentials from Vault). Watchdog alerts are routed to the null receiver. Critical suppresses
warning/info for the same alert.

## Notes

- **Alertmanager** has a TODO comment in the top-level kustomization — there's a vault-ca
  secret name conflict to sort out before it's fully enabled.
- **Testing stacks** are commented out in their kustomization. Kept in the repo as reference
  for how the ingress and NFS/Vault integration were validated.
- **WordPress readiness probe** deliberately hits an NFS-mounted path (`/wp-content/index.php`)
  so NFS outages cause readiness failure — this was a finding from a DR test.
- **MariaDB** uses `nfs-database` storage class (hard mounts, 600s timeout) while WordPress
  uses `nfs-retain` (soft mounts, 30s timeout). The database can't tolerate silent IO errors.

## Related

- [`../infrastructure/`](../infrastructure/) — base layer (namespaces, storage, ingress, Vault injector, CoreDNS, metrics-server)
- [`../../flux/`](../../flux/) — Flux Kustomizations that reconcile this folder
- [`../../../docker-images/`](../../../docker-images/) — container images for remediation and etcd-backup
- [`../../../../deployment-docs/11-vault-k8s-integration-guide.md`](../../../../deployment-docs/11-vault-k8s-integration-guide.md) — end-to-end Vault injection setup
