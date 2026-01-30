# IAM CloudFormation

Phase 1 identity infrastructure - managed policies and GitHub Actions roles.

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

| Policy | Description |
|--------|-------------|
| `HybridCloud-TerraformState-Common` | S3 + DynamoDB state access |
| `HybridCloud-Terraform-SecurityBoundary` | Blocks IAM mutations from Terraform |
| `HybridCloud-NetworkFullManagement` | VPC, subnets, gateways, security groups |
| `HybridCloud-ApplicationFullManagement` | EC2, EKS, ECR management |
| `HybridCloud-SecurityAuditControl` | CloudTrail, CloudWatch, EventBridge, SNS |

## IAM Roles (roles.yaml)

| Role | Purpose | Key Policies |
|------|---------|--------------|
| `GitHubActions-ReadOnly` | Plan/validate only | TerraformState + ReadOnlyAccess |
| `GitHubActions-Network` | Network infrastructure | Network + SecurityBoundary |
| `GitHubActions-Application` | Compute resources | Application + TerraformState |
| `GitHubActions-Audit` | Security & monitoring | SecurityAuditControl |

## Deployment

Both stacks auto-deploy via **CloudFormation Git Sync** when changes are pushed.

**Note:** If both change in same commit, roles may fail (policy dependency).
Fix: Wait for policies to complete, then re-sync roles.

## Dependencies

```
hybrid-foundation (bootstrap)
       │
       ▼
hybrid-policies ──────► Hybrid-GitSync-ServiceRole
  (exports ARNs)           (imports via !ImportValue)
```
