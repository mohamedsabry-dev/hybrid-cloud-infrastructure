# HashiCorp Vault Playbooks

Playbooks for deploying and configuring HashiCorp Vault HA cluster.

## Playbooks

| Playbook | Purpose | Target |
|----------|---------|--------|
| `vault_setup.yml` | Deploy Vault cluster with TLS and KMS unseal | vault_cluster + freeipa |
| `vault_config.yml` | Configure Vault auth, policies, LDAP integration | vault1 (single node) |

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

### 11. vault_config.yml - Shell vs API Modules

**Decision:** How to implement Vault configuration tasks in Ansible

| Option | Chosen |
|--------|--------|
| `community.hashi_vault.vault_write` module (API) | No |
| `ansible.builtin.shell` with vault CLI | **Yes** |

**Rationale:** Initial attempt with `community.hashi_vault` modules faced multiple issues:
- Required `hvac` Python library on target nodes
- Complex idempotency handling (`failed_when` with error message parsing)
- Re-running playbook caused failures ("path already in use")
- Jinja2 template conflicts with Vault Go templates (`{{.UserDN}}`)

Shell approach is simpler:
- Vault CLI is already installed on nodes
- `|| true` handles "already enabled" cases cleanly
- Environment variables (`VAULT_ADDR`, `VAULT_TOKEN`, `VAULT_CACERT`) apply to all commands
- One-time setup playbook doesn't need complex idempotency

**Trade-off:** Shell tasks always show `changed` on re-runs. Acceptable for one-time setup.

### 12. hvac Python Library Dependency

**Decision:** Where to install `hvac` library (required for community.hashi_vault modules)

| Option | Chosen |
|--------|--------|
| Install in vault_config.yml pre_tasks | No |
| Install in ansible_setup.yml (controller only) | No |
| Install in pre_setup.yml (all nodes) | **Yes** |

**Rationale:** Even though we switched to shell commands, `hvac` and `pip` were added to `pre_setup.yml` for future flexibility. All nodes get the dependency during initial setup.

### 13. Jinja2/Vault Template Escaping

**Decision:** How to handle Vault Go template syntax in Ansible playbooks

**Problem:** Vault LDAP config uses `{{.UserDN}}` which conflicts with Ansible Jinja2 templating.

**Solution:** Escape double braces using Jinja2 literal syntax:
```yaml
groupfilter="(member={{ '{{' }}.UserDN{{ '}}' }})"
```

This outputs literal `{{.UserDN}}` to Vault.

**Note:** Ugly but necessary when mixing templating engines.

### 14. Vault Configuration Idempotency

**Decision:** How to handle re-runs of vault_config.yml

| Approach | Chosen |
|----------|--------|
| `changed_when: false` (always report ok) | No |
| Custom `changed_when` logic per task | No |
| Default shell behavior (always changed) | **Yes** |

**Rationale:**
- `changed_when: false` lies about actual changes
- Custom logic unreliable (vault commands have inconsistent output)
- For one-time setup, `changed` status is acceptable and honest

**Principle:** Don't optimize idempotency reporting for playbooks that run once.

### 15. Workflow vs Manual Execution

**Decision:** Which playbooks to include in GitHub workflows

| Playbook | Execution | Chosen |
|----------|-----------|--------|
| `vault_setup.yml` | GitHub Workflow | **Yes** |
| `vault_config.yml` | Manual from Ansible node | **Yes** |

**Rationale:**

The project follows a clear separation pattern:
- **Workflow (automated):** Infrastructure deployment and basic service setup
- **Manual (ansible node):** Internal configuration that requires judgment or one-time sensitive operations

`vault_setup.yml` is appropriate for workflow because:
- Deploys infrastructure (service principals, packages, TLS certs)
- Repeatable and idempotent
- No sensitive output to capture

`vault_config.yml` stays manual because:
- Requires `vault operator init` to run first (manual, one-time)
- Init outputs recovery keys and root token that must be securely captured
- Configuration may need verification before proceeding
- Automating init→save-to-AWS→config adds significant complexity with minimal benefit
- Root token should be revoked after LDAP verification (human judgment)

**Industry Standard:** Vault initialization is almost always manual in production environments. Many organizations require a "key ceremony" with multiple trusted people present. The recovery keys are the most sensitive secrets in the infrastructure.

**Pattern Applied:**
```
Workflow: Deploy LXC → Setup Vault → STOP (display manual steps)
                                        ↓
Manual:   SSH vault1 → init → save keys → run vault_config.yml
```

**Trade-off:** Extra manual step after workflow completes. Acceptable for a one-time operation that happens once per cluster lifetime.

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
