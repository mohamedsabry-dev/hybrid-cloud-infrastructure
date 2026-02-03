# IAM CloudFormation

Phase 1 & 2 identity infrastructure - managed policies and GitHub Actions roles.

## Folder Structure

```
iam/cloudformation/
├── policies/
│   ├── policies.yaml        # Managed policies definitions
│   └── deployment-file.yaml # Git Sync config
└── roles/
    ├── roles.yaml           # IAM roles for GitHub Actions
    └── deployment-file.yaml # Git Sync config
```

## Stacks

| Stack | AWS Name | Purpose |
|-------|----------|---------|
| Policies | `hybrid-policies` | Shared managed policies |
| Roles | `Hybrid-GitSync-ServiceRole` | GitHub Actions OIDC roles |

## Managed Policies (policies.yaml)

| # | Policy | Description |
|---|--------|-------------|
| 1 | `HybridCloud-TerraformState-Common` | S3 + DynamoDB state access |
| 2 | `HybridCloud-Terraform-SecurityBoundary` | Blocks IAM mutations from Terraform |
| 3 | `HybridCloud-NetworkFullManagement` | VPC, subnets, gateways, security groups |
| 4 | `HybridCloud-ApplicationFullManagement` | EC2, EKS, ECR management |
| 5 | `HybridCloud-SecurityAuditControl` | CloudTrail, CloudWatch, EventBridge, SNS |
| 6 | `HybridCloud-SecretsManagement` | Secrets Manager CRUD scoped to `infra/*` |

## IAM Roles (roles.yaml)

All roles use **GitHub OIDC federation** (`sts:AssumeRoleWithWebIdentity`) - no stored access keys.

| # | Role | Purpose | Key Policies |
|---|------|---------|--------------|
| 1 | `GitHubActions-ReadOnly` | Plan/validate only | TerraformState + ReadOnlyAccess |
| 2 | `GitHubActions-Network` | Network infrastructure | Network + SecurityBoundary |
| 3 | `GitHubActions-Application` | Compute resources | Application + TerraformState |
| 4 | `GitHubActions-Audit` | Security & monitoring | SecurityAuditControl |
| 5 | `GitHubActions-Secrets` | Infra secrets (Proxmox, Vault) | SecretsManagement |

## Secrets Management (Phase 2)

The `GitHubActions-Secrets` role manages infrastructure secrets via AWS Secrets Manager.

**Secret naming convention:** All secrets must use the `infra/` prefix.

| Secret | Purpose |
|--------|---------|
| `infra/proxmox/api-token` | Proxmox API token for Terraform provider |
| `infra/vault/unseal-key` | HashiCorp Vault auto-unseal key (future) |
| `infra/vault/root-token` | Vault bootstrap token (future) |

**Workflow usage:**

```yaml
- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::<ACCOUNT_ID>:role/GitHubActions-Secrets
    aws-region: <REGION>

- name: Fetch Proxmox Token
  run: |
    SECRET=$(aws secretsmanager get-secret-value --secret-id infra/proxmox/api-token --query SecretString --output text)
    echo "::add-mask::$SECRET"
    echo "PM_API_TOKEN_SECRET=$SECRET" >> $GITHUB_ENV
```

## Deployment

Both stacks auto-deploy via **CloudFormation Git Sync** when changes are pushed.

**Note:** If both change in same commit, roles may fail (policy dependency).
Fix: Wait for policies to complete, then re-sync roles.

## Dependencies

```
hybrid-foundation (bootstrap)
       │
       ▼
hybrid-policies ──────────► Hybrid-GitSync-ServiceRole
  (exports ARNs)               (imports via !ImportValue)
    │                              │
    ├── TerraformStatePolicy       ├── GitHubActions-Network
    ├── SecurityBoundary           ├── GitHubActions-Application
    ├── NetworkFullManagement      ├── GitHubActions-Audit
    ├── ApplicationFullManagement  └── GitHubActions-Secrets
    ├── SecurityAuditControl
    └── SecretsManagement
```
