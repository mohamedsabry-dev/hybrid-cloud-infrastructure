# AWS IAM module — design notes

Why the IAM shape in this module looks the way it does. The broader 2-tier
IAM model (why `GitHubActions-Infrastructure-{env}` and `GitHubActions-TerraformAdmin-{env}`
exist as two separate roles with different branch scoping) lives in
[`../../../../aws/DESIGN.md`](../../../../aws/DESIGN.md). This file covers
the module-local decisions.

---

## What this module actually provisions

The `Infrastructure-{env}` role — not the `TerraformAdmin-{env}` role.
`TerraformAdmin-{env}` is provisioned by CloudFormation (bootstrap, outside
Terraform) because it's the role Terraform itself uses to run. This module
creates the scoped-down Infrastructure role that day-to-day infra workflows
assume, along with the supporting policies.

Resources:

- `GitHubActions-Infrastructure-{env}` role — trusted by GitHub OIDC on the
  matching branch only
- `wireguard-ssm-role-{env}` + matching instance profile — for the WireGuard
  EC2 to register with AWS SSM Session Manager
- `TerraformState-{env}` policy — S3 + DynamoDB access scoped to this env's
  state path
- `SecurityBoundary-{env}` policy — a DENY policy attached to the
  Infrastructure role

## Why the Infrastructure role has PowerUserAccess + two custom policies

PowerUserAccess gives broad read+write on AWS services but explicitly denies
IAM mutation. That's the right baseline: infra workflows need to create
VPCs, subnets, EC2, Secrets Manager entries, KMS keys — but they should not
be able to create/delete IAM roles, policies, users, or change CloudTrail.

On top of PowerUserAccess:

- `TerraformState-{env}` narrows state access to THIS environment's S3 path
  (`{bucket}/{env}/*`) and the DynamoDB lock table. Without this, dev could
  accidentally modify prod state.
- `SecurityBoundary-{env}` is a DENY policy that adds explicit guardrails
  on top of PowerUserAccess: blocks IAM mutation (belt-and-braces),
  CloudTrail modification, and billing access. Also restricts `PassRole` to
  specific allowed EC2 roles only (prevents using PassRole to hijack
  privileged instance profiles).

## Why DENY instead of just relying on PowerUserAccess's exclusions

PowerUserAccess's IAM exclusion is implicit — a future AWS change to
PowerUserAccess could widen it without warning. An explicit DENY policy is
belt-and-braces: even if the baseline changes, the deny wins in the
evaluation order. For a repo that's supposed to be safe against future AWS
service drift, the extra DENY is cheap insurance.

## OIDC trust scoping — branch-level, not just repo-level

The Infrastructure role's trust policy locks down to:

  repo:{github_repo}:ref:refs/heads/{environment}

This means workflows running on the `dev` branch can assume
`Infrastructure-dev`, but workflows on any other branch (including `prod`,
`main`, feature branches) cannot. It's the branch that controls role
eligibility, not just the repo.

Concrete effect: if someone opened a PR from a feature branch against the
dev branch, the PR workflow would run on the feature-branch ref and would
NOT be able to assume `Infrastructure-dev`. That's intentional — untrusted
PR code shouldn't get cloud creds.

## Relationship to the bigger picture

This module's role (`Infrastructure-{env}`) is the **unprivileged** side of
the 2-tier IAM model. The **privileged** side is `TerraformAdmin-{env}`,
which runs on the `{env}-security` branch and is the only role that can
touch IAM, KMS, and Vault-trust modules. The full reasoning for the 2-tier
split and the security-branch workflow lives in [`../../../../aws/DESIGN.md`](../../../../aws/DESIGN.md).

The `aws/iam/` module itself (this folder) is provisioned by workflows
running under `TerraformAdmin-{env}` — because the Infrastructure role
can't create IAM resources (that's the whole point of the DENY
SecurityBoundary). The pattern is: CloudFormation creates
TerraformAdmin → TerraformAdmin creates Infrastructure + its policies via
this module → Infrastructure does everything else.
