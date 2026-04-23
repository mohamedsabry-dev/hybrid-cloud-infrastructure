# Vault Playbooks — PROD

Ansible playbooks that deploy and configure the 3-node Vault HA cluster on
LXC containers. The Ansible side of the broader Vault story — the full
system overview (cluster architecture, KMS unseal flow, IPA cert cascade,
AWS Secrets Engine for etcd backup) lives in
[`../../../../deployment-docs/vault-overview.md`](../../../../deployment-docs/vault-overview.md).

For setup + init commands see [`vault-setup-guide.txt`](vault-setup-guide.txt).

---

## Playbooks

| Playbook | Purpose | Target |
|----------|---------|--------|
| `vault_setup.yml` | Deploy Vault cluster with TLS + KMS unseal + VIP | `vault_cluster` + `freeipa` |
| `vault_config.yml` | Post-init: auth methods, policies, LDAP, IPA group bindings | `vault1` (single node) |

## Templates

| File | Purpose |
|------|---------|
| `templates/vault.hcl.j2` | Vault server config (KMS seal, Raft, TLS listener, VIP cluster addr, retry_join) |
| `templates/vault.env.j2` | systemd EnvironmentFile for KMS auto-unseal credentials |

AWS credentials for KMS unseal come from one of two sources:
1. **Workflow path** — fetched from AWS Secrets Manager at workflow time, passed as env vars (`VAULT_UNSEAL_ACCESS_KEY`, `VAULT_UNSEAL_SECRET_KEY`). Primary path.
2. **Manual path** — Ansible Vault-encrypted values in `group_vars/vault_cluster.yml`. Fallback for manual runs, gated by the `when:` length check added after TS-VLT-003.

## Decisions specific to the Ansible side

Short notes on choices that live here (the big-picture calls — Raft over Consul, no HAProxy, KMS unseal — are in `vault-overview.md`):

- **DNF repo for Vault binary** — Rocky Linux host, get GPG-verified packages + future `dnf update` path.
- **IPA-signed TLS via Certmonger** — not RPM's placeholder cert, not self-signed. Certmonger handles auto-renewal; zero manual rotation.
- **Dedicated `HTTP/vault{N}.lab.local` service principal per node** — not reusing the host principal. Cleaner cert permissions + room for Kerberos integration later.
- **KMS credentials via systemd EnvironmentFile** (`/etc/vault.d/vault.env`) — not hardcoded in `vault.hcl`, not instance profiles (LXC doesn't have them).
- **Raft storage on local-lvm** — NAS/NFS rejected (UID remapping complexity in unprivileged LXC; Raft is node-local by design).
- **`vault operator init` kept manual** — one-time bootstrap that emits recovery keys + root token; a human must capture the output to AWS Secrets Manager.
- **Shell + Vault CLI in `vault_config.yml`, not `community.hashi_vault`** — hvac Python library + Jinja2/Go-template conflicts (`{{.UserDN}}`) + inconsistent idempotency errors made the API modules more trouble than value for one-time config work.
- **Cert-request idempotency gate** — check cert issuer via `openssl x509 -noout -issuer` (not file-exists; RPM places a placeholder at the same path).

## Troubleshooting

See `troubleshooting/vault/` (repo root):

| Case | Issue |
|------|-------|
| [1](../../../../troubleshooting/vault/1-vault-cluster-initial-setup-investigation.md) | Initial setup (8 sub-issues: GPG, certmonger, CSR, TLS, shell expansion) |
| [2](../../../../troubleshooting/vault/2-freeipa-vip-certificate-san-managedby.md) | VIP SAN cert — missing managedby permissions |
| [3](../../../../troubleshooting/vault/3-vault-kms-credentials-overwrite-empty-vars.md) | KMS credentials empty — manual playbook bypass |
| [4](../../../../troubleshooting/vault/4-vault-agent-injector-k8s-tls-ca-setup.md) | Vault Agent TLS + Go template escaping |

## Related

- [`vault-setup-guide.txt`](vault-setup-guide.txt) — setup + init + config + token revocation commands
- [`../../../../deployment-docs/vault-overview.md`](../../../../deployment-docs/vault-overview.md) — system overview (cluster, KMS, VIP, cert cascade, etcd backup)
- [`../../../../deployment-docs/08-vault-setup-guide.md`](../../../../deployment-docs/08-vault-setup-guide.md) — sequenced step-8 guide in the deployment flow
- [`../freeipa/`](../freeipa/) — IPA setup that must run first (Vault cert + DNS prerequisites)
- [`../../../../terraform/prod/aws/kms-vault-unseal/`](../../../../terraform/prod/aws/kms-vault-unseal/) — AWS-side KMS resources
- [`../../../../terraform/prod/aws/vault-trust/`](../../../../terraform/prod/aws/vault-trust/) — AWS Secrets Engine for etcd backup
