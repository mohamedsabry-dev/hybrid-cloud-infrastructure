# Vault — overview

HashiCorp Vault is a cross-cutting system in this repo. It runs as a 3-node
raft cluster on Proxmox LXCs (external to Kubernetes), issues temporary AWS
credentials to the etcd-backup CronJob via its AWS Secrets Engine, and has
its Agent Injector deployed inside K8s so apps can pull their own secrets
without holding long-lived credentials. Its pieces live across Ansible,
Terraform, Kubernetes, GitHub Actions, and Troubleshooting — this file is
the map that ties those pieces together.

For operational setup, use the sequenced guides:
- `vault-initial-setup-guide.txt` (step 8) — the 3-node cluster itself
- `vault-k8s-integration-guide.txt` (step 11) — Vault ↔ K8s trust + injector
- `k8s-etcd-vault-aws-integration.txt` (step 12) — etcd-backup → Vault → S3

This file is the overview above those guides — what the system is, the key
design calls, and where every piece lives.

---

## Reference

| Item | Dev | Prod |
|------|-----|------|
| Cluster nodes | 10.0.62.10 – 10.0.62.12 (VLAN 62) | 10.0.52.10 – 10.0.52.12 (VLAN 52) |
| VIP (keepalived) | 10.0.62.100 | 10.0.52.100 |
| DNS name | vault.lab.local | vault.lab.local |
| AWS KMS region | us-east-1 | eu-west-2 |
| KMS key alias | alias/vault-unseal | alias/vault-unseal |

Chart version: Vault Helm 0.32.0 (injector only, `server.enabled: false`; the
server lives on LXC, not in K8s).

---

## Design calls

### Raft storage, 3 nodes, HA

Three LXCs running Vault's integrated raft backend. No external consul, no
shared storage, no MySQL backend. Raft gives quorum-based HA with the
simplest operational story: lose one node and the cluster keeps writing;
lose two and it's read-only until a node is recovered.

### TLS via FreeIPA-issued certs

Each node enrolls as an IPA host, Certmonger pulls a cert whose SAN list
covers both the node's own hostname (`vault1.lab.local`, etc.) AND the VIP
name (`vault.lab.local`). This is the only reason every cluster client
can address the VIP over TLS without name-mismatch rejections. The trap
behind making the SAN-for-VIP-hostname work is `TS-VLT-002` — the
`ipa service-mod --addattr=managedby=...` vs `ipa service-add-managedby`
distinction, with a `managedby` grant required on BOTH the service AND the
VIP host object for IPA to issue the cert.

### VIP via keepalived only — NO HAProxy

One virtual IP (`10.0.62.100` / `10.0.52.100`) floats between the 3 nodes
via keepalived. There's no layer-7 load balancer in front. Vault has built-in
request forwarding — if a follower receives a write, it internally forwards
to the leader and returns the leader's response. That means a layer-7 LB
would add zero value: no leader-awareness routing needed, no health-based
removal (keepalived handles that at L3), and TLS termination is exactly the
opposite of what I want (end-to-end TLS is the point).

### AWS KMS auto-unseal over Shamir

Shamir unseal after every restart (paste unseal keys across 3 nodes, 3
times each, 9 manual operations per restart) is operationally intolerable
in a lab where restarts are frequent. KMS auto-unseal: dedicated KMS key
with alias `alias/vault-unseal`, dedicated IAM user `vault_unseal` with
encrypt/decrypt permission on that key only, access keys stored in AWS
Secrets Manager at `<env>/vault/unseal-credentials`, injected by the
Ansible playbook into `/etc/vault.d/vault.env` as systemd EnvironmentFile.
Recovery keys (Shamir master) also stored in AWS Secrets Manager at
`<env>/vault/unseal-keys` for the break-glass case where KMS itself is
unreachable. This introduces a deliberate AWS dependency — validated by
the DR test at `disaster-recovery/vault-aws-kms-credential-loss.md`.

### AWS Secrets Engine for etcd-backup, not long-lived keys

The etcd-backup CronJob needs AWS credentials to upload snapshots to S3.
Two wrong approaches: (1) long-lived IAM user keys stored in a K8s Secret —
defeats the point of running Vault, and (2) IRSA — requires EKS or
self-built OIDC federation, out of scope. The right approach: Vault's AWS
Secrets Engine issues temporary STS credentials on demand. `vault_trust` is
an IAM user that can assume the `etcd-backup` role; Vault uses `vault_trust`'s
keys to mint short-lived credentials scoped to `s3:PutObject` on the backup
bucket. The CronJob gets fresh creds per run, 1-hour TTL, discarded when the
pod exits. Zero long-lived AWS keys anywhere in K8s.

### Injector namespace separation

The Vault Agent Injector webhook deliberately refuses to inject into
`kube-system` (and other system namespaces). The etcd-backup CronJob needs
to run in `kube-system` (so it has access to etcd hostPath). Resolution
was a minor RBAC extension to allow the injector's webhook on `kube-system`
— documented as `TS-K8S-017`. Remediation pod avoided the issue by living
in its own `remediation` namespace.

---

## Layer map — where every Vault-touching file lives

### Ansible

| Path | Purpose |
|------|---------|
| `ansible/<env>/playbooks/vault/vault_setup.yml` | 3-node deploy, Certmonger enrollment, KMS env injection, service start |
| `ansible/<env>/playbooks/vault/vault_config.yml` | Post-init — LDAP auth enable, policies, FreeIPA group-to-policy bindings |
| `ansible/<env>/playbooks/vault/vault_vip.yml` | Keepalived deploy + config for the VIP |
| `ansible/<env>/playbooks/vault/vault-trust-aws.yml` | Enables + configures AWS Secrets Engine; creates `etcd-backup` Vault role |
| `ansible/<env>/playbooks/vault/templates/vault.hcl.j2` | Vault server config template (TLS listener, raft, `seal "awskms"` stanza) |
| `ansible/<env>/playbooks/vault/templates/vault.env.j2` | systemd EnvironmentFile template — KMS AWS creds |
| `ansible/<env>/playbooks/vault/templates/vault-keepalived.conf.j2` | Keepalived template |
| `ansible/<env>/playbooks/k8s/integration-vault-k8s-trust.yml` | Registers K8s token-reviewer JWT in Vault (one-time after cluster up) |
| `ansible/<env>/inventory/group_vars/vault_cluster.yml` | Encrypted KMS creds + LDAP bindpass + keepalived auth password |

### Terraform

| Path | Purpose |
|------|---------|
| `terraform/<env>/proxmox/lxc/vault_cluster/` | 3 LXCs on Proxmox (per-node local-lvm storage, NOT NAS) |
| `terraform/<env>/aws/kms-vault-unseal/` | KMS key + alias + `vault_unseal` IAM user + Secrets Manager entries for creds and recovery keys |
| `terraform/<env>/aws/vault-trust/` | `vault_trust` IAM user + `etcd-backup` IAM role (assume-role chain) + S3 bucket for backups |

### Kubernetes

| Path | Purpose |
|------|---------|
| `kubernetes/<env>/deployments/infrastructure/vault/vault.yaml` | HelmRepository + HelmRelease (injector-only, 2 replicas on control-plane) |
| `kubernetes/<env>/deployments/infrastructure/vault/vault-auth-sa.yaml` | `vault-auth` SA + long-lived token Secret + `system:auth-delegator` ClusterRoleBinding |
| `kubernetes/docs/vault-pod-setup.sh` | Interactive helper — per-app policy + K8s auth role + initial secret values |
| `kubernetes/docs/vault-k8s-pre-setup.txt` | K8s-side prerequisites (cluster CA, issuer URL, token-reviewer JWT) |
| `kubernetes/<env>/deployments/apps/*/vault-ca-secret.yaml` | Per-app IPA CA cert for sidecar TLS trust (wordpress, mariadb, monitoring, alertmanager, remediation, etcd-backup, nginx-test) |

### GitHub Actions

| Path | Purpose |
|------|---------|
| `.github/workflows/<env>-vault-full-setup.yml` | End-to-end: Terraform LXC + Ansible vault_setup + KMS creds fetch |
| `.github/workflows/<env>-aws-kms-vault-unseal.yml` | Terraform apply for the KMS module |
| `.github/workflows/<env>-aws-vault-trust.yml` | Terraform apply for the vault-trust module |
| `.github/workflows/<env>-ansible-full-setup.yml` | Runs ansible with super_bot Kerberos auth |

### Troubleshooting

| TS ID | File | Short |
|-------|------|-------|
| VLT-001 | `troubleshooting/vault/1-vault-cluster-initial-setup-investigation.md` | 8 setup issues bundled — GPG sig, Certmonger `--force`, CSR hostname mismatch, Ansible cert ownership, TLS IP SAN, shell expansion, RPM post-install ordering |
| VLT-002 | `troubleshooting/vault/2-freeipa-vip-certificate-san-managedby.md` | `service-mod --addattr=managedby` vs `service-add-managedby` for cert-with-SAN; managedby must be granted on BOTH service AND VIP host object |
| VLT-003 | `troubleshooting/vault/3-vault-kms-credentials-overwrite-empty-vars.md` | Manual playbook run bypassed GH Actions secret fetch → empty KMS creds templated → added `when:` gate asserting credential length before render |
| VLT-004 | `troubleshooting/vault/4-vault-agent-injector-k8s-tls-ca-setup.md` | Wrong annotation (`agent-extra-secret` vs `tls-secret`); Go template hyphen handling (`{{ index .Data.data "login-password" }}`) |
| VLT-005 | `troubleshooting/vault/5-vault-node-recovery-stale-raft-data.md` | Stale `vault.db` retains old cluster identity; remove `/opt/vault/data/raft` AND `vault.db` before restart |
| K8S-014 | `troubleshooting/kubernetes/14-vault-k8s-auth-service-account-not-authorized.md` | Helm chart-generated SA name didn't match Vault role's `bound_service_account_names` |
| K8S-017 | `troubleshooting/kubernetes/17-vault-injection-system-namespace-denied.md` | Injector webhook RBAC blocks `kube-system`; extend ClusterRole to permit it |
| K8S-024 | `troubleshooting/kubernetes/24-vault-cluster-resilience-2-node-quorum.md` | 2-of-3 raft quorum semantics — understanding majority requirement |
| K8S-033 | `troubleshooting/kubernetes/33-vault-agent-dns-failure-new-pod-blocking.md` | IPA DNS down → CoreDNS forwards fail → sidecar can't resolve vault.lab.local → pod stuck in `Init:0/1` |

### Disaster Recovery

| File | Covers |
|------|--------|
| `disaster-recovery/vault-single-node-down.md` | Single-node failure — quorum maintained, auto-recovery |
| `disaster-recovery/vault-raft-quorum-loss.md` | 2-of-3 down — recovery path via recovery keys |
| `disaster-recovery/vault-aws-kms-credential-loss.md` | AWS KMS unreachable — manual-unseal fallback with recovery keys |
| `disaster-recovery/etcd-backup-s3-validation.md` | End-to-end test — AWS Secrets Engine → STS → S3 upload path |
| `disaster-recovery/network-ipa-dns-outage.md` | FreeIPA down cascade affecting Vault (DNS, certs, service principals) |

### Deployment docs

| File | Purpose |
|------|---------|
| `deployment-docs/vault-initial-setup-guide.txt` | 3-node cluster setup walkthrough (step 8 in sequence) |
| `deployment-docs/vault-k8s-integration-guide.txt` | K8s auth method + injector deployment (step 11) |
| `deployment-docs/k8s-etcd-vault-aws-integration.txt` | etcd-backup → Vault → S3 chain (step 12) |
| `deployment-docs/signal-flows/vault-k8s-auth-signal-flow.txt` | Request trace: pod → Agent → Vault K8s auth → token → secret |
| `deployment-docs/aws-secrets-setup-guide.txt` | AWS Secrets Manager entries this depends on (prerequisite) |

---

## Dependency footprint

### Vault depends on

- **FreeIPA** — DNS for `vault.lab.local` and `vault1/2/3.lab.local`; IPA CA for TLS cert issuance (via Certmonger on each node); Kerberos host principals; LDAP auth for human UI login via `vault_bind` service account
- **AWS KMS** — auto-unseal key per env, in the env's AWS account
- **AWS Secrets Manager** — holds `vault_unseal` access keys AND the raft recovery keys (the break-glass credentials)
- **Proxmox vzdump** — LXC container backups on the NAS (restore path for full-node loss scenarios)

### Consumers of Vault

Every app with `vault.hashicorp.com/agent-inject: "true"` annotation. Current
consumers:

- `wordpress` — DB credentials injected as env-file
- `mariadb` — root + app DB credentials
- `monitoring` (kube-prometheus-stack) — Grafana admin password, datasource credentials
- `alertmanager` (dev only today) — SMTP + receiver credentials
- `remediation` — Proxmox API token (the system's only external-mutation credential)
- `etcd-backup` CronJob — STS credentials via AWS Secrets Engine (the only consumer of that path)
- `testing/nginx-test` — smoke test for injection pattern

Each consumer follows the same pattern: dedicated ServiceAccount + long-lived
token Secret + IPA CA secret in its own namespace + Vault annotations on the
Deployment/StatefulSet. Details in `vault-k8s-integration-guide.txt`.

### What breaks if Vault is unavailable

- Existing pods with cached Vault tokens keep working until TTL (~1 hour)
- New pods with inject annotations stuck in `Init:0/1` — sidecar can't auth
- etcd-backup CronJob fails to get AWS creds; next scheduled snapshot is missed
- LDAP-based UI login fails; break-glass userpass auth still works
- Automatic secret rotations fail

The 3-node raft gives resilience against single-node failure. The SPOF risk
is "all 3 nodes unreachable simultaneously" (power event, network partition,
hypervisor loss). Mitigation is the Proxmox vzdump restore path.

See `disaster-recovery/README.md` for the full SPOF acknowledgment.

---

## Why this overview exists

Vault is the one system in this platform that doesn't cleanly live in one
layer. The install is Ansible, the AWS side is Terraform, the consumers are
Kubernetes, the automation is GitHub Actions, the failure history is in
`troubleshooting/`, and the test coverage is in `disaster-recovery/`. Someone
trying to understand Vault by reading the repo would otherwise need to open
nine folders. This file is the map that gets them from "what is this?" to
"where does this specific piece live?" in one skim.

The setup guides (`vault-initial-setup-guide.txt` etc.) cover HOW to deploy.
The TS cases cover WHAT went wrong when. This file covers WHAT IT IS and
WHERE IT LIVES — the missing layer between those two.
