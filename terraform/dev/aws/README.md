# AWS Terraform Modules — DEV

Six modules that provision the AWS side of the hybrid-cloud environment.
Applied via GitHub Actions workflows on the `dev` or `dev-security` branch.

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
| [`network/`](network/) | dev | Infrastructure | VPC, IGW, subnets, Route53 private zone |
| [`compute/`](compute/) | dev | Infrastructure | WireGuard EC2, SG, EIP, VPC route to on-prem |
| [`iam/`](iam/) | dev-security | TerraformAdmin | Infrastructure role + SecurityBoundary + SSM profile |
| [`kms-vault-unseal/`](kms-vault-unseal/) | dev-security | TerraformAdmin | KMS auto-unseal key + dedicated IAM user |
| [`vault-trust/`](vault-trust/) | dev-security | TerraformAdmin | AWS Secrets Engine user + etcd-backup role + S3 |
| [`secrets/`](secrets/) | dev | Infrastructure | Secrets Manager containers (values populated out-of-band) |

The `dev-security` modules create IAM/KMS resources and run under
`TerraformAdmin-dev` (elevated). The `dev` modules run under
`Infrastructure-dev` (scoped down, no IAM mutation).

## State isolation

Each module has its own state file at `dev/aws/{module}/terraform.tfstate`
in the dev S3 backend. Modules that depend on each other use
`terraform_remote_state` data sources — no shared state, no cross-env access.

## Related

- [`../../../aws/DESIGN.md`](../../../aws/DESIGN.md) — 2-tier IAM model, region decisions, bootstrap rationale
- [`../../../aws/bootstrap.md`](../../../aws/bootstrap.md) — CloudFormation bootstrap (creates TerraformAdmin + state backend)
- [`../../../.github/workflows/`](../../../.github/workflows/) — workflows that apply these modules
- [`../../prod/aws/`](../../prod/aws/) — prod mirror (eu-west-2, VLAN 50-55)
