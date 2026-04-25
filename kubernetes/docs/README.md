# Kubernetes Operational Docs

Runbooks, setup guides, and operational procedures for the k8s clusters.
These are "how I did it" docs — not design reasoning (that lives in DESIGN.md files
next to the code).

---

## Flux

| Doc | What it covers |
|-----|----------------|
| [local-kubectl-flux-setup.md](flux/local-kubectl-flux-setup.md) | Mac Mini → on-prem cluster access for `kubectl` and `flux diff` |
| [flux-restructuring-operation-guide.md](flux/flux-restructuring-operation-guide.md) | Safe Kustomization split procedure (written after TS-K8S-019) |
| [flux-add-folder-guide.txt](flux/flux-add-folder-guide.txt) | Adding a new watched folder to Flux |
| [flux-patch-operation.txt](flux/flux-patch-operation.txt) | Patching Flux controller config without editing gotk-components |

## Vault

| Doc | What it covers |
|-----|----------------|
| [vault-k8s-pre-setup.txt](vault/vault-k8s-pre-setup.txt) | Pre-setup commands for Vault k8s auth (CA cert, token, OIDC) |
| [vault-pod-setup.sh](vault/vault-pod-setup.sh) | Interactive Vault login helper script |

## K8s Cluster

| Doc | What it covers |
|-----|----------------|
| [install_etcdctl.txt](k8s/install_etcdctl.txt) | etcdctl installation matching cluster version |

## Apps

| Doc | What it covers |
|-----|----------------|
| [mariadb-sc-migration.md](apps/mariadb-sc-migration.md) | StorageClass migration runbook: nfs-retain → nfs-database (hard mount) |

---

## Related

- **Integration & deployment procedures** — see [`../../deployment-docs/`](../../deployment-docs/)
- **Troubleshooting cases** — see [`../../troubleshooting/kubernetes/`](../../troubleshooting/kubernetes/)
