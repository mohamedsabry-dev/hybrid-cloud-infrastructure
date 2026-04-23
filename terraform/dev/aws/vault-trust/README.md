# AWS Vault-Trust Module — DEV

Provisions the AWS-side pieces for Vault's AWS Secrets Engine: a dedicated
IAM user (`vault_trust`) that can assume a narrow role (`etcd-backup`), the
S3 bucket for etcd snapshots, and the Secrets Manager entry holding
vault_trust's access keys.

This module is the AWS counterpart to the Ansible playbook
`ansible/dev/playbooks/vault/vault-trust-aws.yml`, which takes these
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
| `aws_secretsmanager_secret` | `dev/vault/aws-secrets-engine-credentials` | Stores `vault_trust`'s access keys (Ansible fetches these) |

## File structure

| File | Purpose |
|------|---------|
| `iam.tf` | `vault_trust` user + `etcd-backup` role + trust + permission policies |
| `s3.tf` | etcd backup bucket definition |
| `secrets.tf` | Secrets Manager resources |
| `main.tf` | Module composition |
| `provider.tf` | TerraformAdmin role OIDC + backend config |

## Outputs

No outputs exported yet — nothing currently consumes this module via
remote state. I'll add `outputs.tf` when another module or workflow
actually needs to reference these resources; no point wiring up exports
that nobody reads.

## Dependencies

- `iam` module — reuses identity baseline
- This module runs under `TerraformAdmin-dev` (security-branch workflow) because it creates IAM resources

## Related

- [`DESIGN.md`](DESIGN.md) — why STS over long-lived keys, why not IRSA, the assume-role chain rationale
- [`../../../../deployment-docs/vault-overview.md`](../../../../deployment-docs/vault-overview.md) — "AWS Secrets Engine for etcd-backup" design call
- [`../../../../deployment-docs/12-etcd-backup-integration-guide.md`](../../../../deployment-docs/12-etcd-backup-integration-guide.md) — full integration walkthrough
- [`../../../../ansible/dev/playbooks/vault/vault-trust-aws.yml`](../../../../ansible/dev/playbooks/vault/vault-trust-aws.yml) — Ansible side that configures Vault to use this
- [`../../../../.github/workflows/dev-aws-vault-trust.yml`](../../../../.github/workflows/dev-aws-vault-trust.yml) — apply workflow (runs on `dev-security` branch)
- [`../kms-vault-unseal/`](../kms-vault-unseal/) — the OTHER Vault-AWS integration (auto-unseal)
