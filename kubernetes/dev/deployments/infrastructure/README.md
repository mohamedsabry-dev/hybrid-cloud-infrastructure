# Infrastructure — DEV Environment

Base-layer Kubernetes resources deployed via Flux before any application
workloads. Everything here is either a cluster prerequisite (namespaces,
storage classes, priority classes) or a shared service that apps depend on
(ingress, DNS, Vault injection, metrics).

All Helm charts are managed as Flux `HelmRelease` objects — no manual
`helm install` anywhere. Kustomize stitches the subfolders together.

---

## Directory layout

```
infrastructure/
├── README.md                  # this file
├── kustomization.yaml         # top-level Kustomization (order = list order)
├── namespaces/
│   ├── kustomization.yaml
│   └── namespaces.yaml        # monitoring, logging, apps, testing, vault, database, ingress-nginx
├── priority-classes/
│   ├── kustomization.yaml
│   └── priority-classes.yaml  # database-critical (1M), app-standard (500k)
├── storage/
│   ├── kustomization.yaml
│   ├── nfs-csi-driver.yaml    # CSI driver Helm chart (2 controller replicas, workers-only)
│   └── storageclass.yaml      # nfs-retain, nfs-delete, nfs-database
├── vault/
│   ├── kustomization.yaml
│   ├── vault.yaml             # Vault Agent Injector Helm chart (external Vault, no in-cluster server)
│   └── vault-auth-sa.yaml     # SA + token + ClusterRoleBinding for Vault K8s auth
├── ingress/
│   ├── kustomization.yaml
│   └── ingress-nginx-controller.yaml  # ingress-nginx Helm chart (NodePort 30080/30443)
├── coredns/
│   ├── kustomization.yaml
│   ├── coredns-custom.yaml    # full Corefile with hosts block (Vault VIP + K8s VIP)
│   └── coredns-patch.yaml     # pin to control-plane + pod anti-affinity
└── metrics-server/
    ├── kustomization.yaml
    └── metrics-server.yaml    # metrics-server Helm chart (2 replicas, HA)
```

## What each subfolder does

| Folder | What | Key details |
|--------|------|-------------|
| `namespaces` | Pre-creates all namespaces | 7 namespaces, all labeled `managed-by: flux` |
| `priority-classes` | Scheduling priority tiers | `database-critical` preempts `app-standard` — databases survive resource pressure |
| `storage` | NFS-backed persistent storage | CSI driver + 3 StorageClasses against Synology NAS (`10.0.40.120:/volume1/k8s-dev`). `nfs-database` uses `hard` mounts with longer timeouts |
| `vault` | Vault Agent Injector | Points to external Vault HA cluster at `vault.lab.local:8200`. Server is disabled — Vault runs on dedicated LXCs, not in K8s |
| `ingress` | Ingress controller | ingress-nginx on NodePort 30080/30443. External Nginx LXC handles TLS termination and forwards here |
| `coredns` | Cluster DNS customization | Hosts block maps `vault.lab.local` → Vault VIP and `k8s.lab.local` → K8s VIP. Pinned to control-plane nodes with anti-affinity |
| `metrics-server` | Node/pod resource metrics | Feeds `kubectl top` and HPA. `--kubelet-insecure-tls` because kubeadm uses self-signed kubelet certs |

## HA and placement

I run 2 replicas of everything that supports it, with pod anti-affinity to
spread across nodes. Placement rules:

- **CoreDNS** — control-plane only (hard anti-affinity, hard nodeSelector)
- **Vault Injector** — control-plane only (same pattern)
- **NFS CSI controller** — workers only (control-plane excluded via node affinity)
- **Ingress / Metrics-server** — any node (soft or hard anti-affinity across hostnames)

## Storage classes

| Class | Reclaim | Mount | Use case |
|-------|---------|-------|----------|
| `nfs-retain` | Retain | `soft`, 30s timeout | General persistent data (Grafana, Prometheus) |
| `nfs-delete` | Delete | `soft`, 30s timeout | Ephemeral volumes, testing |
| `nfs-database` | Retain | `hard`, 600s timeout, `intr` | MariaDB, PostgreSQL — survives brief NAS hiccups without data corruption |

All three point to the same NAS share. The difference is mount behavior and
reclaim policy. I went with `nfs-database` using `hard` mounts because a
database silently eating IO errors on a `soft` mount is worse than blocking
until the NAS comes back.

## Notes

- **Descheduler** is commented out in `kustomization.yaml` — I had it here
  initially but it doesn't need any special treatment so it can be re-enabled
  when needed.
- **Remediation** is in `../apps/` not here, because it needs Vault Agent
  injection and has to deploy after the injector is ready.
- **No `nfsvers=4`** — the Synology NAS is on NFSv3 only. The `nolock`
  option is there because NFSv3 lock manager was flaky across VLANs.

## Related

- [`../apps/`](../apps/) — application-layer deployments (monitoring, logging, databases, remediation)
- [`../../flux/`](../../flux/) — Flux Kustomizations that point to this folder
- [`../../../../deployment-docs/11-vault-k8s-integration-guide.md`](../../../../deployment-docs/11-vault-k8s-integration-guide.md) — how Vault injection is set up end-to-end
- [`../../../../network/ip-planning.txt`](../../../../network/ip-planning.txt) — VLAN/subnet reference
