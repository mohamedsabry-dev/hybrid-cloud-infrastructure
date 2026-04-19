# AWS Vault-Trust Module — PROD

Provisions the AWS-side pieces for Vault's AWS Secrets Engine: a dedicated
IAM user (`vault_trust`) that can assume a narrow role (`etcd-backup`), the
S3 bucket for etcd snapshots, and the Secrets Manager entry holding
vault_trust's access keys.

This module is the AWS counterpart to the Ansible playbook
`ansible/prod/playbooks/vault/vault-trust-aws.yml`, which takes these
resources and wires them into Vault.

For the "why" — STS temp-credentials vs long-lived IAM keys, IRSA not
available on self-managed k8s — see [`DESIGN.md`](DESIGN.md).

---

## Resources

| Resource | Name | Purpose |
|----------|------|---------|
| `aws_iam_user` | `vault_trust` | Identity Vault's AWS Secrets Engine authenticates as |
| `aws_iam_access_key` | — | Credentials for `vault_trust` |
| `aws_iam_role` | `etcd-backup` | Assumed role with `s3:PutObject` on the backup bucket |
| `aws_iam_policy` (inline) | — | `sts:AssumeRole` permission for `vault_trust` → `etcd-backup` |
| `aws_s3_bucket` | etcd backup bucket | Destination for etcd snapshots |
| `aws_secretsmanager_secret` | `prod/vault/aws-secrets-engine-credentials` | Stores `vault_trust`'s access keys (Ansible fetches these) |

## File structure

| File | Purpose |
|------|---------|
| `iam.tf` | `vault_trust` user + `etcd-backup` role + trust + permission policies |
| `s3.tf` | etcd backup bucket definition |
| `secrets.tf` | Secrets Manager resources |
| `main.tf` | Module composition |
| `provider.tf` | TerraformAdmin role OIDC + backend config |

## Outputs

| Output | Description |
|--------|-------------|
| `vault_trust_user_arn` | ARN of the vault_trust IAM user |
| `etcd_backup_role_arn` | ARN of the etcd-backup assumable role |
| `etcd_backup_bucket` | S3 bucket name for etcd snapshots |
| `credentials_secret_arn` | ARN of the Secrets Manager entry |

## Dependencies

- `iam` module — reuses identity baseline
- This module runs under `TerraformAdmin-prod` (security-branch workflow) because it creates IAM resources

## Related

- [`DESIGN.md`](DESIGN.md) — why STS over long-lived keys, why not IRSA, the assume-role chain rationale
- [`../../../../deployment-docs/vault-overview.md`](../../../../deployment-docs/vault-overview.md) — "AWS Secrets Engine for etcd-backup" design call
- [`../../../../deployment-docs/k8s-etcd-vault-aws-integration.txt`](../../../../deployment-docs/k8s-etcd-vault-aws-integration.txt) — full integration walkthrough
- [`../../../../ansible/prod/playbooks/vault/vault-trust-aws.yml`](../../../../ansible/prod/playbooks/vault/vault-trust-aws.yml) — Ansible side that configures Vault to use this
- [`../../../../.github/workflows/prod-aws-vault-trust.yml`](../../../../.github/workflows/prod-aws-vault-trust.yml) — apply workflow (runs on `prod-security` branch)
- [`../kms-vault-unseal/`](../kms-vault-unseal/) — the OTHER Vault-AWS integration (auto-unseal)
