# Kubernetes

Everything that runs on the two on-prem k8s clusters (dev and prod), managed end-to-end
through Flux GitOps. Each cluster is a kubeadm-bootstrapped HA setup (3 masters, 3 workers)
running on Proxmox VMs — provisioned by Ansible, reconciled by Flux from this repo.

---

## Folder Layout

```
kubernetes/
├── dev/                  # Dev cluster (branch: dev)
│   ├── flux/             # Flux controllers + sync config
│   └── deployments/
│       ├── infrastructure/   # Base layer: namespaces, storage, Vault, CoreDNS, ingress, metrics
│       └── apps/             # App layer: monitoring, logging, MariaDB, WordPress, remediation, etcd-backup
├── prod/                 # Prod cluster (branch: prod) — mirrors dev with higher specs
│   ├── flux/
│   └── deployments/
│       ├── infrastructure/
│       └── apps/
├── docker-images/        # Custom container images (remediation + etcd-backup)
└── docs/                 # Operational runbooks and setup guides
    ├── flux/
    ├── vault/
    ├── k8s/
    └── apps/
```

## How It Works

Flux watches the git branch matching each environment (`dev` branch → `kubernetes/dev/flux`,
`prod` branch → `kubernetes/prod/flux`). Two Kustomizations per cluster:

1. **infrastructure-sync** — reconciles base resources first (CRDs, operators, storage
   classes, Vault agent injector, CoreDNS, ingress, metrics-server). Has a health check
   on `vault-agent-injector` — apps won't start until Vault injection is ready.

2. **apps-sync** — depends on infrastructure. Reconciles all application workloads
   (monitoring stack, logging, databases, WordPress, remediation, etcd-backup).

This ordering exists because of TS-K8S-012 — CRD race conditions caused Flux to try
deploying HelmReleases before their CRDs existed. The health check on Vault came from
TS-K8S-019 where apps started before the injector was ready, causing a cascade of
crashlooping pods.

## Dev vs Prod

Both environments are structurally identical — same files, same folders. The differences
are all configuration:

| What | Dev | Prod |
|------|-----|------|
| Workers | 2 (4GB each, worker3 shut down) | 3 (2.75GB each) |
| Git branch | `dev` | `prod` |
| Subnet | 10.0.6x | 10.0.5x |
| NFS share | `/volume1/k8s-dev` | `/volume1/k8s-prod` |
| Prometheus storage | 20Gi | 50Gi |
| Loki storage / retention | 50Gi / 7 days | 100Gi / 14 days |
| Grafana storage | 5Gi | 10Gi |
| MariaDB storage | 15Gi | 50Gi |
| WordPress storage | 15Gi | 30Gi |
| WordPress HPA | 2-3 replicas | 2-4 replicas |
| Ingress replicas | 2 | 3 |
| AWS region (etcd backup) | us-east-1 | eu-west-2 |

I write dev first, then mirror to prod with the env/subnet/sizing swaps.

## Key Patterns

**Vault sidecar injection** — every workload that needs secrets uses the same pattern:
a ServiceAccount + `vault-ca-secret` + pod annotations. The Vault agent injector
(deployed in infrastructure layer) handles the rest. No hardcoded credentials anywhere.

**NFS storage classes** — three classes on the Asustor NAS, each for a different use case:
- `nfs-retain` — soft mount, 30s timeout. For stateful apps that can tolerate brief NFS
  hiccups (Grafana, Prometheus, Loki).
- `nfs-delete` — soft mount. For ephemeral/testing workloads.
- `nfs-database` — hard mount, 600s timeout, interruptible. For databases (MariaDB) where
  data integrity matters more than availability during NFS blips.

**On-prem self-healing** — the remediation system handles what Kubernetes can't: VM-level
failures. A Python script watches worker node Ready status and escalates through
reboot → reset → restore-from-backup via the Proxmox API. Runs on masters only
(firewall requirement — only master VLAN reaches Proxmox port 8006).

**Standalone Alertmanager** — separated from the kube-prometheus-stack Helm chart so it
can use Vault-injected SMTP credentials (Gmail app password). The Helm chart's built-in
Alertmanager doesn't support sidecar injection.

## Custom Images

Two images published to GHCR, used by deployments in both environments:

- **remediation** — Python 3.11 with kubectl, proxmoxer, and network debugging tools.
  The actual script is mounted via ConfigMap (logic changes don't need a rebuild).
- **etcd-backup** — Alpine with etcdctl, AWS CLI, and kubectl for daily etcd snapshots
  to S3.

See [`docker-images/README.md`](docker-images/README.md) for build commands.

## Docs

Operational runbooks live in [`docs/`](docs/README.md) — Flux procedures, Vault setup,
etcdctl installation, MariaDB migration guide. These are "how I did it" references,
not architecture docs.

Design reasoning lives in `DESIGN.md` files next to the code:
- [`dev/flux/DESIGN.md`](dev/flux/DESIGN.md) — Flux architecture decisions and incident-driven evolution
- [`dev/deployments/apps/remediation/DESIGN.md`](dev/deployments/apps/remediation/DESIGN.md) — self-healing system design
- [`DESIGN.md`](DESIGN.md) — top-level kubernetes design decisions
