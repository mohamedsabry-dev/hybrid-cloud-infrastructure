# HashiCorp Vault Playbooks

Playbooks for deploying and configuring HashiCorp Vault HA cluster.

## Playbooks

| Playbook | Purpose | Target |
|----------|---------|--------|
| `vault_setup.yml` | Deploy Vault cluster with TLS and KMS unseal | vault_cluster + freeipa |
| `vault_config.yml` | Configure Vault policies and auth (TODO) | vault_cluster |

## Templates

| File | Purpose |
|------|---------|
| `templates/vault.hcl.j2` | Vault server configuration |
| `templates/vault.env.j2` | AWS credentials for KMS auto-unseal |

### vault.env.j2

AWS credentials for KMS auto-unseal. Credentials can be provided via:
1. **Environment variables** (workflow) - `VAULT_UNSEAL_ACCESS_KEY`, `VAULT_UNSEAL_SECRET_KEY`
2. **Ansible Vault** (manual testing) - See `group_vars/vault_cluster.yml`

### vault.hcl.j2

Vault configuration with:
- AWS KMS auto-unseal (us-east-1, alias/vault-unseal)
- Raft storage backend (local-lvm per node)
- TLS using FreeIPA-signed certificates
- 3-node HA cluster with retry_join

## Deployment

### Prerequisites
1. FreeIPA server running with DNS
2. Vault nodes provisioned and joined to domain
3. AWS KMS key created (alias/vault-unseal)

### Setup Steps

```bash
# 1. Run vault_setup playbook (creates service principals, deploys Vault)
ansible-playbook playbooks/vault/vault_setup.yml

# 2. Initialize Vault (MANUAL - one time only on vault1)
ssh root@vault1.lab.local
source /etc/profile.d/vault.sh
vault operator init -recovery-shares=5 -recovery-threshold=3

# 3. Save recovery keys and root token securely!

# 4. Check cluster status
vault status
vault operator raft list-peers
```

---

## Decision Log

### 1. Package Installation Method

**Decision:** How to install the Vault binary on vault nodes

| Option | Chosen |
|--------|--------|
| HashiCorp APT repo (Debian/Ubuntu only) | No |
| HashiCorp YUM/DNF repo (RHEL-family) | **Yes** |
| Direct binary download | No |

**Rationale:** Vault nodes run Rocky Linux 10 (RHEL-family). DNF repo provides GPG-verified packages, dependency resolution, and future upgrade path via `dnf update`.

**Trade-off:** Requires explicit `rpm_key` task in addition to `yum_repository`. Binary download would be simpler but loses package management.

### 2. TLS Certificate Source

**Decision:** Which CA to use for Vault node TLS certificates

| Option | Chosen |
|--------|--------|
| Keep RPM-generated self-signed placeholder certs | No |
| Generate custom self-signed certs via Ansible | No |
| Request IPA-signed certs via Certmonger | **Yes** |

**Rationale:** All nodes are IPA-enrolled. IPA-signed certs are trusted automatically via `/etc/ipa/ca.crt`. Certmonger handles auto-renewal with post-save hook — zero manual rotation ever.

**Trade-off:** Requires FreeIPA service principal creation first. More setup steps than self-signed but eliminates all manual cert rotation permanently.

### 3. FreeIPA Service Principal

**Decision:** Whether to create dedicated `vault/` principal or reuse `host/`

| Option | Chosen |
|--------|--------|
| Use existing `host/vault1.lab.local` principal | No |
| Create dedicated `vault/vault1.lab.local` per node | **Yes** |
| Skip service principal, use self-signed certs | No |

**Rationale:** Isolates cert permissions, enables independent cert lifecycle, follows PKI best practice. Cleaner for future Kerberos integration with Vault LDAP auth method.

### 4. AWS Credential Injection for KMS Unseal

**Decision:** How to provide AWS credentials to the Vault process

| Option | Chosen |
|--------|--------|
| Hardcode in vault.hcl (access_key/secret_key fields) | No |
| EC2 instance profile/IAM role | No (not available on LXC) |
| Environment variables via systemd EnvironmentFile | **Yes** |
| HashiCorp vault-env tool | No |

**Rationale:** Hardcoding is a security anti-pattern. Instance profiles require EC2 — not available on LXC. RPM-shipped systemd unit already references `EnvironmentFile=/etc/vault.d/vault.env` making this the natural integration point.

**Trade-off:** Ansible Vault is a temporary store — planned migration to AWS Secrets Manager once Vault is operational. `vault.env` must be mode 0600 owned by vault user.

### 5. Vault Storage Backend

**Decision:** Which storage backend to use for Vault HA

| Option | Chosen |
|--------|--------|
| HashiCorp Consul (traditional HA backend) | No |
| Integrated Raft storage (built-in) | **Yes** |
| External database (MySQL, PostgreSQL) | No |

**Rationale:** Raft eliminates need for separate Consul cluster. `local-lvm` provides dedicated isolated storage — running out of Raft space will not crash the OS. Simpler operational model with no external dependency.

**Trade-off:** NAS/NFS mounts explicitly rejected due to UID remapping complexity in unprivileged LXC. Raft data is node-local by design for consensus.

### 6. TLS File Paths

**Decision:** Where to store Vault TLS certificate and key files

| Option | Chosen |
|--------|--------|
| `/etc/vault.d/tls/` (config directory) | No |
| `/opt/vault/tls/` (RPM default) | **Yes** |

**Rationale:** RPM post-install creates `/opt/vault/tls` and places placeholder certs there. Certmonger overwrites them at the same path. IPA CA cert at `/etc/ipa/ca.crt` referenced directly in vault.hcl — no copy needed.

### 7. Vault Initialization

**Decision:** Whether to automate `vault operator init` in the playbook

| Option | Chosen |
|--------|--------|
| Automate in Ansible with idempotency gate | No |
| Run manually once on vault1 only | **Yes** |

**Rationale:** Init is a one-time bootstrap that generates root token and recovery keys. Automating risks accidental re-initialization. A human must be present to save the recovery keys securely.

**Principle:** Automate repeatable ops, keep one-time sensitive operations manual.

### 8. VAULT_ADDR Environment

**Decision:** How to ensure `VAULT_ADDR` and `VAULT_CACERT` are available

| Option | Chosen |
|--------|--------|
| Set per-command using environment variable prefix | No |
| Add to `/root/.bashrc` per node | No |
| Deploy via `/etc/profile.d/vault.sh` system-wide | **Yes** |

**Rationale:** `profile.d` sourced for all users on every interactive login, survives reboots. `inventory_hostname` ensures each node gets its own correct address. `VAULT_CACERT=/etc/ipa/ca.crt` used instead of `VAULT_SKIP_VERIFY=1` for proper TLS validation.

**Trade-off:** `profile.d` not sourced in non-interactive shells (Ansible ad-hoc). For Ansible tasks must source explicitly or use the `environment:` key in playbook tasks.

### 9. Idempotency Gate for Cert Request

**Decision:** How to make `ipa-getcert request` task idempotent

| Option | Chosen |
|--------|--------|
| Check if cert file exists (stat module) | No |
| Check cert issuer (openssl x509 -noout -issuer) | **Yes** |
| Always run with --force flag | No (flag doesn't exist) |

**Rationale:** `--force` does not exist in installed certmonger version. File existence check fails because RPM creates placeholder at same path. Issuer check distinguishes HashiCorp placeholder from real IPA-signed cert.

### 10. Unseal Mechanism

**Decision:** Which unseal mechanism to use for the Vault cluster

| Option | Chosen |
|--------|--------|
| Standard Shamir secret sharing (manual unseal keys) | No |
| AWS KMS auto-unseal | **Yes** |

**Rationale:** Manual unseal requires human intervention every restart. Unacceptable for a 3-node HA cluster. KMS auto-unseal means nodes unseal themselves on restart with zero intervention. Recovery keys only needed if KMS becomes unavailable.

**Trade-off:** Creates dependency on AWS KMS availability. Mitigated by AWS KMS high availability SLA.

---

## Architectural Principles

| Principle | Application |
|-----------|-------------|
| Manual before automation | Init kept manual. Repeatable steps automated via Ansible |
| Idempotency first | Every task designed safe to re-run without side effects |
| Secrets hygiene | No credentials hardcoded. AWS creds in Ansible Vault or env vars |
| PKI integration | FreeIPA CA for all TLS. No self-signed certs in final state |
| Local storage for Raft | NAS/NFS rejected. local-lvm per node for isolation |
| Zero-touch unseal | AWS KMS ensures cluster recovers from restarts without intervention |
| Consistent tooling | ansible_freeipa collection for FreeIPA ops |

---

## Troubleshooting

See `/troubleshooting/vault/` (repo root) for detailed issue resolutions:

| Case | Issue |
|------|-------|
| [25](../../../../troubleshooting/vault/25-vault-gpg-signature-validation-failure.md) | GPG signature validation failure on install |
| [26](../../../../troubleshooting/vault/26-certmonger-force-flag-not-recognized.md) | ipa-getcert --force flag not recognized |
| [27](../../../../troubleshooting/vault/27-freeipa-ca-rejected-csr-hostname-mismatch.md) | FreeIPA CA rejected CSR (hostname mismatch) |
| [28](../../../../troubleshooting/vault/28-ansible-cert-ownership-task-file-absent.md) | Cert ownership task file absent |
| [29](../../../../troubleshooting/vault/29-vault-tls-ip-san-error.md) | vault status TLS IP SAN error |
| [30](../../../../troubleshooting/vault/30-ansible-shell-expansion-wrong-node.md) | $(hostname -f) expanding on control node |
| [31](../../../../troubleshooting/vault/31-ansible-cert-check-missing-file-fatal.md) | Cert issuer check failing on missing file |
| [32](../../../../troubleshooting/vault/32-rpm-postinstall-task-ordering.md) | RPM post-install task ordering |
