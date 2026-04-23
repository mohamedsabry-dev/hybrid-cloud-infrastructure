# AWS KMS Vault Unseal Module — DEV

Provisions the AWS-side pieces Vault needs for auto-unseal: the KMS key,
a dedicated IAM user, and two Secrets Manager entries holding the IAM
credentials and the Vault recovery keys.

For the "why" — KMS vs Shamir, dedicated user, key policy tiers, recovery
key storage — see [`DESIGN.md`](DESIGN.md).

---

## Resources

| Resource | Name | Purpose |
|----------|------|---------|
| KMS Key | `vault-unseal-key` | Encrypt/decrypt Vault master key (auto-unseal) |
| KMS Alias | `alias/vault-unseal` | Stable alias Vault config references |
| IAM User | `vault-unseal` | Dedicated service account used ONLY for unseal |
| IAM Access Key | — | Credentials for the `vault-unseal` user |
| Secret | `dev/vault/unseal-credentials` | Stores the IAM access key / secret key |
| Secret | `dev/vault/unseal-keys` | Stores Vault recovery keys (populated post-init) |

## File structure

| File | Purpose |
|------|---------|
| `kms.tf` | KMS key + alias + IAM policy (identical dev/prod) |
| `user.tf` | IAM user + access key (identical dev/prod) |
| `secret.tf` | Secrets Manager resources (identical dev/prod) |
| `outputs.tf` | Key + secret ARNs (identical dev/prod) |
| `variables.tf` | Env-specific config |
| `provider.tf` | Backend + provider config |

## Populating recovery keys after Vault init

The `dev/vault/unseal-keys` secret is created with a placeholder. After
Vault is initialized (manual step, one-time), the recovery keys returned
by `vault operator init` must be stored here. Procedure + commands:

  deployment-docs/vault-initial-setup-guide.txt
  deployment-docs/vault-overview.md

## Related

- [`DESIGN.md`](DESIGN.md) — KMS auto-unseal rationale, key policy tiers, recovery key storage
- [`../vault-trust/`](../vault-trust/) — the OTHER Vault-AWS integration (AWS Secrets Engine for etcd-backup)
- [`../../../../.github/workflows/dev-aws-kms-vault-unseal.yml`](../../../../.github/workflows/dev-aws-kms-vault-unseal.yml) — apply workflow (runs on `dev-security` branch, elevated privileges)
- [`../../../../deployment-docs/vault-overview.md`](../../../../deployment-docs/vault-overview.md) — how Vault consumes this
- [`../../../../deployment-docs/vault-initial-setup-guide.txt`](../../../../deployment-docs/vault-initial-setup-guide.txt) — recovery-key storage procedure
