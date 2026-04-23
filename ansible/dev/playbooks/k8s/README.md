# Kubernetes Playbooks — DEV

Ansible playbooks that initialize + operate the Kubernetes cluster. The Ansible
side handles the bootstrap (kubeadm init/join, HAProxy + Keepalived for the
API VIP, Flux CD bootstrap, node tooling, Vault-K8s trust). Post-bootstrap,
Flux takes over and reconciles everything else from git.

For the Flux app/infra loop reasoning see [`../../../../kubernetes/dev/flux/DESIGN.md`](../../../../kubernetes/dev/flux/DESIGN.md).
For the Vault-K8s integration story see [`../../../../deployment-docs/vault-overview.md`](../../../../deployment-docs/vault-overview.md).
For sequenced deploy steps see [`../../../../deployment-docs/09-k8s-setup-guide.md`](../../../../deployment-docs/09-k8s-setup-guide.md) and [`../../../../deployment-docs/10-k8s-flux-setup-guide.md`](../../../../deployment-docs/10-k8s-flux-setup-guide.md).

---

## Playbooks

| Playbook | Purpose | Target |
|----------|---------|--------|
| `k8s_setup.yml` | Prep nodes (kubeadm packages, HAProxy+Keepalived, CNI prereqs) | `k8s_masters`, `k8s_workers` |
| `k8s_init.yml` | `kubeadm init` on master1 + `kubeadm join` on masters 2/3 and workers | `k8s` |
| `k8s_important_tools.yml` | Install tools on the cluster (metrics-server, etc.) | `k8s_masters` |
| `k8s_hosts_fallback.yml` | Populate `/etc/hosts` fallback entries on nodes (IPA-down mitigation) | `k8s` |
| `flux_setup.yml` | One-time Flux CD bootstrap on master1 (`flux bootstrap github`) | `k8s-master1` |
| `integration-vault-k8s-trust.yml` | Register K8s token-reviewer JWT with Vault's Kubernetes auth method | `vault_cluster` |
| `worker-nfs-mount.yml` | Mount NFS volumes on workers (pre-CSI manual path; kept for ops) | `k8s_workers` |
| `worker-nfs-unmount.yml` | Unmount NFS volumes on workers | `k8s_workers` |

## Supporting directories

- `tasks/` — reusable task files used by the playbooks (join token generation, etc.)
- `templates/` — Jinja templates (HAProxy config, keepalived config, Flux sync templates, etc.)
- `drafts/` — work-in-progress playbooks not yet wired into the flow

## When these run

- `k8s_setup.yml` + `k8s_init.yml` — invoked by `{env}-k8s-full-setup.yml` workflow
- `flux_setup.yml` — invoked by `{env}-k8s-full-setup.yml` at the end, or manually. One-time per cluster (see `deployment-docs/10-k8s-flux-setup-guide.md` for the GitHub PAT prerequisites)
- `integration-vault-k8s-trust.yml` — invoked manually after Vault is initialized AND the K8s cluster is up; part of the step-11 Vault-K8s integration in deployment-docs sequence

## Related

- [`../../../../kubernetes/dev/flux/DESIGN.md`](../../../../kubernetes/dev/flux/DESIGN.md) — Flux app/infra split reasoning, healthCheck pattern, TS-K8S-012/019/042
- [`../../../../deployment-docs/09-k8s-setup-guide.md`](../../../../deployment-docs/09-k8s-setup-guide.md) — step-9 K8s cluster setup walkthrough
- [`../../../../deployment-docs/10-k8s-flux-setup-guide.md`](../../../../deployment-docs/10-k8s-flux-setup-guide.md) — step-10 Flux bootstrap walkthrough
- [`../../../../deployment-docs/11-vault-k8s-integration-guide.md`](../../../../deployment-docs/11-vault-k8s-integration-guide.md) — step-11 Vault-K8s trust walkthrough
- [`../../../../deployment-docs/12-etcd-backup-integration-guide.md`](../../../../deployment-docs/12-etcd-backup-integration-guide.md) — step-12 etcd-backup via Vault AWS SE
