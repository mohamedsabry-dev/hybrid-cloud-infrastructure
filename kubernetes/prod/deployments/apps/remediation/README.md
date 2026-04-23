# Remediation — worker node self-healing

Single-replica Deployment on a K8s master that watches worker node Ready status and remediates via the Proxmox API when a worker goes NotReady (escalating: reboot → reset → restore from backup). Fills the on-prem gap between "K8s can't fix a broken VM" and "I can't destroy-and-recreate in a homelab with IPA-enrolled pet VMs."

## Files in this folder

| File | Purpose |
|------|---------|
| [`DESIGN.md`](DESIGN.md) | The **why** — evolution story, design decisions, what got rejected and why, production-vs-homelab framing, known limitations |
| [`SETUP.md`](SETUP.md) | The **one-time provisioning log** — firewall rules, Proxmox API user/token, Vault secret/policy/role, K8s resources (from the 2026-04-07 first deploy) |
| `namespace.yaml` | Dedicated `remediation` namespace (required because Vault injector can't touch `kube-system` by default — see `[TS-K8S-017]`) |
| `priorityclass.yaml` | `self-healing-critical` PriorityClass |
| `remediation-auth-sa.yaml` | ServiceAccount + read-only ClusterRole (nodes: get/list/watch only) |
| `configmap.yaml` | The Python remediation script (canonical source of truth for behavior) |
| `deployment.yaml` | The Deployment (1 replica, master-only via nodeSelector+toleration, Vault-injected Proxmox creds) |
| `vault-ca-secret.yaml` | IPA CA cert so the vault-agent sidecar trusts Vault's TLS |
| `kustomization.yaml` | Stitches the above together for Flux |

## Quick operational notes

- **1 replica** — Runs on master, no leader election. See DESIGN.md for why 2 replicas + leader election was rejected.
- **Master-only placement** — `nodeSelector: node-role.kubernetes.io/control-plane: ""` + master toleration. Only the master VLAN can reach Proxmox on port 8006 (MikroTik ACL).
- **No pod-level checking** — K8s handles pod failures natively; this script only handles what K8s can't (broken VMs). DESIGN.md explains the evolution.
- **5-minute check interval + 2-minute verify window** — minimum 7 minutes from first NotReady observation to first remediation action.
- **Alerts via Alertmanager API** — not direct SMTP. Alertmanager runs on the same master class, so the availability domain matches.
- **Restore runs at most once per node per incident** — dump-VMID-existence guard; manual reset required to retry.

## Related folders

- [`../../../../deployment-docs/vault-k8s-integration-guide.txt`](../../../../deployment-docs/vault-k8s-integration-guide.txt) — the Vault injection pattern this Deployment follows
- [`../../../../disaster-recovery/README.md`](../../../../disaster-recovery/README.md) — DR hub (partial-worker-loss test validates this system)
- [`../../../../docker-images/remediation/`](../../../../docker-images/remediation/) — the container image (includes ps/netcat/dig/etc. for debugging)
- [`../../../../troubleshooting/kubernetes/17-vault-injection-system-namespace-denied.md`](../../../../troubleshooting/kubernetes/17-vault-injection-system-namespace-denied.md) — the injection-namespace TS case that drove the dedicated `remediation` namespace
