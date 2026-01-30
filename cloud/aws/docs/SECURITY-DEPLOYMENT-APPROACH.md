# Infrastructure Deployment Security Approach

## Overview

This document outlines the security model for deploying infrastructure in this repository.

## Deployment Model

```
+------------------------------------------+
|        LAYER 1: Foundation               |
|        (Manual Deploy Only)              |
|                                          |
|  - IAM Roles & Policies                  |
|  - OIDC Provider                         |
|  - Permission Boundaries                 |
|  - CloudTrail / Audit                    |
|                                          |
|  Tool: CloudFormation (Console/CLI)      |
|  Git Sync: DISABLED                      |
+------------------------------------------+
                    |
                    v
+------------------------------------------+
|        LAYER 2: Infrastructure           |
|        (Automated via GitHub Actions)    |
|                                          |
|  - S3 Buckets, DynamoDB                  |
|  - VPCs, Subnets, EC2                    |
|  - Application IAM (with boundaries)     |
|                                          |
|  Tool: Terraform + GitHub Actions        |
+------------------------------------------+
```

## Security Controls

### 1. IAM & Foundation Resources

| Aspect | Approach |
|--------|----------|
| Deployment Method | Manual (AWS Console or CLI) |
| Git Sync | Disconnected |
| Templates Location | `/cloud/aws/iam/`, `/cloud/aws/bootstrap/cloudformation/` |
| Change Process | PR review -> Merge -> Admin deploys manually |
| Automation | None (intentional) |

**Rationale**: IAM resources are too sensitive for automated deployment. A human must review and execute changes to prevent privilege escalation.

### 2. Infrastructure Resources (Terraform)

| Aspect | Approach |
|--------|----------|
| Deployment Method | GitHub Actions |
| Trigger | `workflow_dispatch` (manual) + `push` (feature branch testing) |
| IAM Permissions | No `iam:*` - only infrastructure actions |
| Runner | Self-hosted `production` runner |

### 3. Code Review Requirements (CODEOWNERS)

Protected paths requiring approval from `@mohamedsabrydev`:

| Path | Reason |
|------|--------|
| `/cloud/aws/iam/` | IAM templates |
| `/cloud/aws/bootstrap/cloudformation/` | Bootstrap CloudFormation |
| `/cloud/aws/bootstrap/**/backend.tf` | Terraform state config |
| `/cloud/aws/bootstrap/**/providers.tf` | Provider config |
| `/.github/workflows/tf-bootstrap.yml` | Production deploy workflow |
| `/.github/workflows/setup-providers.yml` | Provider mirror workflow |
| `/.github/CODEOWNERS` | This protection itself |

### 4. Branch Protection (GitHub)

Required settings for `main` branch:
- Require pull request before merging
- Require at least 1 approval
- Require review from Code Owners
- Do not allow bypassing (applies to admins too)

## Change Workflows

### Changing IAM/Foundation Resources

```
1. Developer creates PR with template changes
2. Security team reviews (CODEOWNERS enforced)
3. PR merged to main
4. Trusted admin deploys manually via AWS Console/CLI
5. Admin verifies change
```

### Changing Infrastructure (Terraform)

```
1. Developer creates PR with Terraform changes
2. Push to feature branch triggers plan (optional)
3. PR reviewed and merged
4. workflow_dispatch or push triggers apply
```

## What GitHub Actions CANNOT Do

The GitHub Actions IAM role intentionally lacks:
- `iam:CreateUser`, `iam:CreateRole`, `iam:*Policy*`
- `organizations:*`
- `account:*`

This prevents privilege escalation even if workflows are compromised.

## Future Enhancements

| Enhancement | Purpose |
|-------------|---------|
| Runner Groups | Restrict which workflows can use `production` runner |
| OIDC Subject Claims | Restrict IAM role to specific branches only |
| Environment Protection | Require manual approval before production deploys |
| OPA/Conftest | Policy-as-code validation before deploy |
