# AWS IAM Module — PROD

Provisions the `GitHubActions-Infrastructure-prod` role (the unprivileged
tier used by day-to-day infra workflows), its supporting policies, and the
WireGuard SSM role + instance profile.

For the "why" — 2-tier IAM split, DENY-based SecurityBoundary, branch-scoped
OIDC trust — see [`DESIGN.md`](DESIGN.md). For apply/migration commands see
[`iam-operation-guide.txt`](iam-operation-guide.txt).

---

## Resources

| Resource | Name | Description |
|----------|------|-------------|
| `aws_iam_role` | `GitHubActions-Infrastructure-prod` | OIDC-federated role for infra workflows |
| `aws_iam_role` | `wireguard-ssm-role-prod` | EC2 role for SSM Session Manager |
| `aws_iam_instance_profile` | `wireguard-ssm-profile-prod` | Instance profile attached to the WireGuard EC2 |
| `aws_iam_policy` | `TerraformState-prod` | S3/DynamoDB state access scoped to this env |
| `aws_iam_policy` | `SecurityBoundary-prod` | DENY policy (blocks IAM mutation, CloudTrail, billing) |

## Policy scope

### `TerraformState-prod`
- S3: `ListBucket`, `GetObject`, `PutObject`, `DeleteObject` on `{bucket}/prod/*`
- DynamoDB: `GetItem`, `PutItem`, `DeleteItem` on the lock table

### `SecurityBoundary-prod`
DENY on:
- IAM mutation (create/delete/attach roles, policies, users)
- CloudTrail modifications
- Billing / Cost Management
- `PassRole` except for specifically allowed EC2 roles

## OIDC trust

The role trusts `token.actions.githubusercontent.com` with the condition:

  repo:{github_repo}:ref:refs/heads/prod

Only workflows running on the `prod` branch can assume this role. Other
branches (including feature branches, `main`, `dev`) cannot.

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `environment` | Env name | `prod` |
| `account_id` | AWS account ID | *sensitive, passed via workflow* |
| `github_repo` | GitHub repo (`owner/repo`) | — |
| `state_bucket_name` | S3 bucket holding Terraform state | — |
| `lock_table_name` | DynamoDB state-lock table | — |
| `region` | AWS region | `eu-west-2` |

## Outputs

| Output | Description |
|--------|-------------|
| `terraform_state_policy_arn` | ARN of the `TerraformState-prod` policy |
| `security_boundary_policy_arn` | ARN of the `SecurityBoundary-prod` policy |
| `infrastructure_role_arn` | ARN of the GitHub Actions infra role |
| `infrastructure_role_name` | Name of the GitHub Actions infra role |
| `wireguard_instance_profile_name` | Instance profile name for the WireGuard EC2 |

## Related

- [`DESIGN.md`](DESIGN.md) — why this shape (2-tier IAM, DENY SecurityBoundary, branch-scoped OIDC)
- [`iam-operation-guide.txt`](iam-operation-guide.txt) — apply, post-apply compute re-run, historical state migrations
- [`../../../../aws/DESIGN.md`](../../../../aws/DESIGN.md) — broader 2-tier IAM model + prod-security branch rationale
- [`../../../../aws/bootstrap.md`](../../../../aws/bootstrap.md) — CloudFormation bootstrap (source of the TerraformAdmin role that runs this module)
- [`../../../../.github/workflows/prod-aws-iam.yml`](../../../../.github/workflows/prod-aws-iam.yml) — the workflow that applies this module
- [`../compute/`](../compute/) — consumes `wireguard_instance_profile_name` via remote state
