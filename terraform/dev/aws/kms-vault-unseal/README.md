# AWS KMS Vault Unseal Module

Manages KMS key and IAM user for HashiCorp Vault auto-unseal.

## Resources Created

| Resource | Name | Purpose |
|----------|------|---------|
| KMS Key | `vault-unseal-key` | Encrypt/decrypt Vault master key |
| KMS Alias | `alias/vault-unseal` | Human-readable key reference |
| IAM User | `vault-unseal` | Service account for Vault |
| IAM Access Key | - | Credentials for Vault |
| Secret | `dev/vault/unseal-credentials` | Stores IAM credentials |
| Secret | `dev/vault/unseal-keys` | Stores Vault recovery keys |

## Usage

After Vault initialization, store recovery keys:

```bash
aws secretsmanager put-secret-value \
  --secret-id dev/vault/unseal-keys \
  --secret-string '{"key1":"xxx","key2":"xxx","key3":"xxx","key4":"xxx","key5":"xxx","root":"xxx"}'
```

## File Structure

| File | Purpose |
|------|---------|
| `kms.tf` | KMS key with IAM policy (identical dev/prod) |
| `user.tf` | IAM user and access key (identical dev/prod) |
| `secret.tf` | Secrets Manager resources (identical dev/prod) |
| `outputs.tf` | Key and secret ARNs (identical dev/prod) |
| `variables.tf` | Environment-specific configuration |
| `provider.tf` | Backend and provider config |
