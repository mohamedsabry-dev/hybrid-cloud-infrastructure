# AWS layer — design notes and reasoning

How the AWS side of this project came to be. Iteration history and decisions behind the bootstrap, account structure, state backends, IAM model, and region choices. Reads as a narrative, not a runbook — for the practical deploy steps, resources, and admin access see [`bootstrap.md`](bootstrap.md) and [`README.md`](README.md).

---

A few things in this layer don't make sense without the story. I went through several iterations before landing on the current design — here's how I got here and why.

## 1. Why two AWS accounts, not one

I considered running everything under a single account, using IAM to separate dev and prod workloads. I ended up rejecting that for two reasons:

- **Future multi-organization integration.** I want the option to wire a second AWS Organization into this setup later (demo, client, subscription change) without having to tear the design apart. Two accounts from day one mean that story is already half-written.
- **Mirror the on-prem split.** Dev and prod are completely separated on the Proxmox side — two hypervisors, two VLAN blocks, two ansible trees, two k8s clusters. Running them through a single AWS account would break the mirror and create a spaghetti of cross-tag IAM conditions. Two accounts keep the model clean: whatever is true for dev on-prem is true for dev on AWS.

Cost: two bootstrap stacks, two sets of admin users, two regions. Accepted — separation of concern was worth more than the duplication.

## 2. Why two mirrored state backends, not one shared

My first attempt was a single S3 bucket and a single DynamoDB lock table, both in one account, with cross-account IAM letting the other account read/write its own prefix.

It broke down fast:

- DynamoDB cross-account locking had sharp edges I didn't want to babysit.
- I ended up needing more privilege on one account than the other just to keep the state backend working — the opposite of clean separation.
- Maintenance started looking like spaghetti (which role can write which path, from which account) for what should be a simple "each env owns its own state" problem.

So I switched to two fully mirrored backends — each account owns its own state bucket and lock table. No cross-account IAM for state, no weird privilege asymmetry.

## 3. Why CloudFormation for the bootstrap, not Terraform

I first tried managing *everything* in CloudFormation, including full IAM, using the CFN git-sync feature. Two problems killed that path:

- **Git-sync triggering.** Sync either runs on every push to a branch (I don't want that for IAM) or requires manual console actions each time (defeats the automation goal).
- **No dependency ordering during apply.** I hit cases where a role referenced a policy that hadn't been created yet — CFN fired them in parallel, the role failed while the policy succeeded, and I had to manually clean up and retry. Not sustainable.

OK, so why not just do all of it in Terraform instead? **Privilege escalation.** If the Terraform role can modify IAM, a bad plan can silently widen it — remove a boundary, add a passthrough, etc. I wanted a layer that Terraform itself cannot touch.

The current split resolves both concerns:

- **CloudFormation does exactly one thing, once per account.** It creates the OIDC provider, the state backend, the `TerraformAdmin` role with a `PermissionsBoundary`, and the admin user. That's the bootstrap.
- **The `PermissionsBoundary` explicitly denies modification of those bootstrap resources.** Even `TerraformAdmin` — even a Terraform plan running under it — cannot delete the state bucket, remove the boundary, destroy the OIDC provider, or alter the `TerraformAdmin` role itself. That's the privilege-escalation fence.

One YAML, run once as AWS root user. After that, Terraform takes over.

## 4. Why the 2-tier IAM roles, and where the `dev-security` branch came from

From the CFN-created `TerraformAdmin-{env}` role I wanted to manage the rest of IAM via Terraform — but I did not want the day-to-day `Infrastructure-{env}` role (the one that creates VPCs, EC2, Secrets, etc.) to have any IAM permissions itself.

So I used `TerraformAdmin-{env}` to create `Infrastructure-{env}` via Terraform:

```
CFN bootstrap:  TerraformAdmin-{env}   (admin + PermissionsBoundary)
                     │
                     │  creates via Terraform
                     ▼
                Infrastructure-{env}   (PowerUser, no IAM mutation, SecurityBoundary)
```

`Infrastructure-{env}` is locked down with a `SecurityBoundary` that denies `iam:*`, `cloudtrail:*`, and billing actions. It can do everything it needs to provision infra, and nothing it needs to escalate.

The two roles fire from different branches:

- `TerraformAdmin-{env}` from `{env}-security` (IAM, KMS, Vault trust)
- `Infrastructure-{env}` from `{env}` (VPC, EC2, Secrets values, etc.)

**This is where the `dev-security` / `prod-security` branch pattern actually came from.** It wasn't a branching-strategy decision made upfront — it emerged naturally from the role split. I wanted a separate review gate for anything that fires the stronger role, and a separate branch is the simplest way to enforce that. The branch-flow diagrams in `github/deployment-pattern.md` are downstream of this — the origin is here.

## 5. Why these regions — and why prod ended up mixed

Both environments started in `eu-west-2` (London). I picked London because it's the closest AWS region to Egypt (~65ms from home, versus ~120ms to US regions). For interactive work that 55ms is noticeable.

**Dev moved first.** After the Reserved Instance purchase failure (see [`dev-account-migration.md`](dev-account-migration.md)), I migrated the whole dev environment to `us-east-1`. I could have moved only the workload (network + compute) and kept the state backend in London, but I migrated everything for consistency — clean split, no mixed-region dev setup to keep in my head.

**Prod moved later, partially.** While running the tunnels from London I kept hitting intermittent WireGuard instability between my ISP and the AWS elastic IP in eu-west-2. Full investigation is in [`../troubleshooting/network/5-wireguard-tunnel-stability-investigation.md`](../troubleshooting/network/5-wireguard-tunnel-stability-investigation.md) — after ruling out NAT timeout, keepalive settings, CGNAT, and several other theories across four phases, the cleanest path forward was moving the prod VPN endpoint off the London IP.

So I moved **just prod's network and compute** (VPC + WireGuard EC2) to `us-east-1` and left everything else in `eu-west-2`:

| Prod resource | Region | Why |
|---------------|--------|-----|
| State backend (S3 + DynamoDB) | eu-west-2 | Already working, no reason to move |
| IAM roles (`TerraformAdmin-prod`, `Infrastructure-prod`) | eu-west-2 | Not latency-sensitive |
| KMS for Vault auto-unseal | eu-west-2 | Stays close to where on-prem Vault pulls unseal keys |
| Vault-trust IAM user | eu-west-2 | Same reason |
| Secrets Manager values | eu-west-2 | Fetched by workflows, not latency-critical |
| VPC + WireGuard EC2 | **us-east-1** | Moved to escape the London-IP tunnel instability |

I accepted the drift from a "pure mirror" because the non-compute resources don't care about latency and I'd rather not re-migrate working infra. Side effect: prod compute is now in the same region as dev compute, which simplifies anything cross-env later (routing, observability).
