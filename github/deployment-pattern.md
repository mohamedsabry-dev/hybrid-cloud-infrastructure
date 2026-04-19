# Deployment Workflow Pattern

How code flows from development to production.

---

## Why two branch paths instead of one

Most changes use the standard `dev → prod → main` path. But any change that
touches IAM or security (AWS roles, policies, permission boundaries, KMS,
Vault trust) takes an extra detour through `dev-security` and
`prod-security` branches before reaching `prod`.

I did this for one reason: blast radius. A bad Terraform change on the
infrastructure side typically recreates a VM or a security group — recovery
is a revert + re-apply. A bad change on the IAM side can silently grant
over-scoped permissions, remove a permission boundary, or widen a KMS
policy in ways that are hard to spot in a plan and are not always revertable
cleanly (IAM changes in CloudTrail are the evidence, not a rollback button).

So I gated IAM-touching workflows behind their own branches:
- `dev-aws-iam`, `dev-aws-kms-vault-unseal`, `dev-aws-vault-trust` trigger
  on `dev-security`, not `dev`.
- Same for prod: `prod-aws-iam`, `prod-aws-kms-vault-unseal`,
  `prod-aws-vault-trust` trigger on `prod-security`, not `prod`.

These workflows also assume a different IAM role
(`GitHubActions-TerraformAdmin-{env}`, scoped for IAM/KMS) instead of the
standard `GitHubActions-Infrastructure-{env}`. So even if someone pushed
IAM Terraform to the wrong branch, the role the workflow can assume would
not allow the change.

The longer merge path is the review gate. Every transition (`dev → dev-security`,
`dev-security → prod-security`, `prod-security → prod`) requires a PR with
approval, so an IAM change gets eyes on it multiple times before the prod
role actually fires.

Cost: a slower loop for IAM iteration. Worth it — IAM is exactly the place
I want to iterate slowly.

---

## Standard Changes (No IAM)

**Path:** `dev` → `prod` → `main`
**Use for:** Proxmox VMs, LXCs, infrastructure changes (no IAM/security)

```
┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐
│  dev    │────▶│  Test   │────▶│  prod   │────▶│  main   │
│ (push)  │     │  Pass   │     │  (PR)   │     │  (PR)   │
└─────────┘     └─────────┘     └─────────┘     └─────────┘
     │                              │               │
     ▼                              ▼               ▼
Infrastructure-dev            Infrastructure-prod   Milestone
workflow runs                 workflow runs         complete
```

### Steps

1. Push changes to `dev` branch
2. Infrastructure-dev workflow runs automatically
3. Test and verify in DEV environment
4. Create PR from `dev` → `prod` (requires review & approval)
5. Merge PR → Infrastructure-prod workflow runs
6. Test and verify in PROD environment
7. When phase/milestone complete: PR from `prod` → `main`

---

## IAM/Security Changes

**Path:** `dev` → `dev-security` → `prod-security` → `prod` → `main`
**Use for:** IAM roles, policies, permissions, security configurations

```
┌─────────┐     ┌──────────────┐     ┌───────────────┐     ┌─────────┐
│  dev    │────▶│ dev-security │────▶│ prod-security │────▶│  prod   │
│ (push)  │     │    (PR)      │     │     (PR)      │     │  (PR)   │
└─────────┘     └──────────────┘     └───────────────┘     └─────────┘
                      │                    │                    │
                      ▼                    ▼                    ▼
                TerraformAdmin-dev   TerraformAdmin-prod   Infrastructure-prod
                workflow runs        workflow runs         workflow runs
```

### Steps

1. Push changes to `dev` branch (test infrastructure first)
2. Create PR from `dev` → `dev-security` (requires review)
3. Merge PR → TerraformAdmin-dev workflow runs (IAM changes in DEV AWS)
4. Test and verify IAM/security in DEV environment
5. Create PR from `dev-security` → `prod-security` (requires review)
6. Merge PR → TerraformAdmin-prod workflow runs (IAM changes in PROD AWS)
7. Create PR from `prod-security` → `prod` (infrastructure deployment if needed)
8. When phase/milestone complete: PR from `prod` → `main`

---

## Path Summary

| Change Type | Branch Path |
|-------------|-------------|
| Infrastructure | `dev` → `prod` → `main` |
| IAM/Security | `dev` → `dev-security` → `prod-security` → `prod` → `main` |

---

## PR Requirements

| Target Branch | Review Required | CI Checks |
|---------------|-----------------|-----------|
| `main` | Yes (1+) | Required |
| `prod` | Yes (1+) | Required |
| `prod-security` | Yes (1+) | Required |
| `dev-security` | Yes (1+) | - |
| `dev` | No | - |
---
