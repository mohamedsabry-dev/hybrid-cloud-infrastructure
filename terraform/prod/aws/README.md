# AWS Terraform Modules — PROD

Six modules that provision the AWS side of the hybrid-cloud environment.
Applied via GitHub Actions workflows on the `prod` or `prod-security` branch.

For the broader AWS design (2-tier IAM, CloudFormation bootstrap, region
decisions) see [`../../../aws/DESIGN.md`](../../../aws/DESIGN.md).

---

## Module dependency order

```
network          (base — VPC, subnets, Route53)
    │
    ├─► compute  (WireGuard EC2, EIP, SG, home route)
    │       ▲
    │       │
iam ────────┘    (Infrastructure role, SSM profile, policies)

kms-vault-unseal (KMS key, unseal IAM user, secrets)

vault-trust      (vault_trust IAM user, etcd-backup role, S3 bucket)

secrets          (11 Secrets Manager entries — placeholder containers)
```

## Modules

| Module | Branch | Role | Purpose |
|--------|--------|------|---------|
| [`network/`](network/) | prod | Infrastructure | VPC, IGW, subnets, Route53 private zone |
| [`compute/`](compute/) | prod | Infrastructure | WireGuard EC2, SG, EIP, VPC route to on-prem |
| [`iam/`](iam/) | prod-security | TerraformAdmin | Infrastructure role + SecurityBoundary + SSM profile |
| [`kms-vault-unseal/`](kms-vault-unseal/) | prod-security | TerraformAdmin | KMS auto-unseal key + dedicated IAM user |
| [`vault-trust/`](vault-trust/) | prod-security | TerraformAdmin | AWS Secrets Engine user + etcd-backup role + S3 |
| [`secrets/`](secrets/) | prod | Infrastructure | Secrets Manager containers (values populated out-of-band) |

The `prod-security` modules create IAM/KMS resources and run under
`TerraformAdmin-prod` (elevated). The `prod` modules run under
`Infrastructure-prod` (scoped down, no IAM mutation).

## State isolation

Each module has its own state file at `prod/aws/{module}/terraform.tfstate`
in the prod S3 backend. Modules that depend on each other use
`terraform_remote_state` data sources — no shared state, no cross-env access.

## Related

- [`../../../aws/DESIGN.md`](../../../aws/DESIGN.md) — 2-tier IAM model, region decisions, bootstrap rationale
- [`../../../aws/bootstrap.md`](../../../aws/bootstrap.md) — CloudFormation bootstrap (creates TerraformAdmin + state backend)
- [`../../../.github/workflows/`](../../../.github/workflows/) — workflows that apply these modules
- [`../../dev/aws/`](../../dev/aws/) — dev mirror (us-east-1, VLAN 60-65)
