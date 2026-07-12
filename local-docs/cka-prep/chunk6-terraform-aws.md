# Interview Questions — Chunk 6: Terraform + AWS
Extracted from chunk reviews. My voice, my tone.

---

### Q1: How did you use Terraform in your project?

I used Terraform to create both Proxmox and AWS resources. On the Proxmox side — VMs, LXC containers, storage, backup retention periods. On AWS — compute, networking, secrets, IAM. I have 2 mirrored environments, dev and prod, across 2 AWS accounts and 2 Proxmox hosts.

Terraform runs via assumed roles scoped to the target privilege level. State is stored in S3 buckets with scoped subfolders per module — no local state — plus DynamoDB state locking, one per account.

> Stop here. Let them ask about the scope. Don't volunteer the 2-tier IAM unless they pull it.

**If they ask about the IAM scope:**

I have 2 assume roles — one for infrastructure administration without IAM operations, and one for IAM operations plus the rest. Each role is authorized to run only from its specific GitHub Actions workflow — prod infra from the prod workflow, IAM from the prod-security workflow. This prevents privilege escalation — the infra workflow can't create IAM roles, and the security workflow is a separate trigger.

**If they ask how those roles were created:**

The bootstrap layer is AWS CloudFormation, not Terraform. CloudFormation creates the OIDC federation, both IAM assume roles, the S3 state bucket, DynamoDB lock table, and a local web user account with policies. There's also an IAM permission boundary (that's the term) to prevent the Terraform IAM role from overriding or misusing any resources created by CloudFormation.

**If they ask about the plan/apply workflow:**

I have 2 ways. First, a local read-only account pointed at dev only — I validate the code, check format, and run plan locally. Then I push to dev, the GitHub Actions workflow triggers with plan and apply. There's a gate simulated as a 3-minute wait with a cancel option to review before it applies. I considered real approval gates but they're not available on the free or pro GitHub plan.

> Key signal: layered answer. Start with what Terraform does, let them pull the IAM depth, let them pull the bootstrap depth. Each layer shows more security thinking. Don't dump it all at once.

### Q2: Did you use Terraform modules or write your own?

I started with raw resources intentionally — for learning. I wanted to understand what each resource does before abstracting it. Over time, with variables and core settings in each main.tf, the config files naturally turned into a small version of modularization — each resource scope lives in its own folder, and I can copy the folder to another environment, edit the vars and the provider block, and it works. So it's modular by structure, not by the Terraform module registry pattern.

**If asked about dev/prod separation:**

I use a complete mirror of the code — dev and prod in separate folders, not shared modules with tfvars. This lets me develop freely on dev, test, edit, break things, and only ship to prod via PR after dev is complete and the workflow passes. The merge review is easy — you just look at what changed under the prod folder. It also allows intentional drift between dev and prod in the future without conflict, since this is dev-prod, not stage-prod. Dev is a sandbox for iteration, not a staging gate.

> Key signal: "raw resources first for learning, then natural modularization" shows you understand modules but chose a deliberate path. The dev/prod separation answer shows you thought about the tradeoff (DRY vs freedom to iterate) and made a justified call. If they push "but that's code duplication" — answer: "yes, and that's intentional. Dev needs to diverge safely. Shared modules would force lockstep, which defeats the purpose of having a dev environment."

### Q3: How do you manage Terraform providers in your environment?

I use a local provider mirror for both the AWS provider and the BPG Proxmox provider. The provider packages are saved into a local folder, and I configure the path in `.terraformrc` to point `terraform init` to that local directory instead of downloading from the registry every time. So the sequence is: GitHub Actions workflow triggers → `terraform init` runs → Terraform reads `.terraformrc` → sees the filesystem_mirror config → uses the local cached provider binary instead of hitting the registry.

> Why this matters: faster init, no external dependency during CI runs, consistent provider versions. If asked "why not just let it download?" — reliability. CI shouldn't fail because a registry is slow or unreachable.
>
> Gap to review: confirm the exact `.terraformrc` config syntax and how `filesystem_mirror` vs `network_mirror` works.

---

## Project-specific (likely follow-ups from Q1-Q3)

### Q4: How do you handle secrets in Terraform?

No secrets in Terraform code or state. AWS credentials come via OIDC federation — the GitHub Actions workflow assumes an IAM role, gets short-lived STS tokens, no static keys anywhere. For Proxmox, the API token is stored in GitHub Actions secrets and passed as an environment variable. Sensitive values in Terraform use `sensitive = true` to hide them from plan output.

> If pushed: "What about the state file?" — state is in S3 with bucket encryption enabled. Even if someone reads the state, secrets aren't stored as plain resources — they're references, not values.

### Q5: How does your Terraform connect to both Proxmox and AWS?

Two separate provider configurations. AWS provider uses OIDC-assumed role credentials from the workflow. Proxmox uses the BPG provider with API token auth. They live in separate folders — `terraform/dev/proxmox/` and `terraform/dev/aws/` — so they don't share state or provider config. Each one has its own state file in S3 under a scoped subfolder.

### Q6: What happens if someone needs to change infrastructure outside of Terraform?

Drift. Next `terraform plan` will show the difference and want to bring it back to the declared state. In my project this hasn't been a real issue because I'm the only operator. But in a team, the answer is: don't. All changes go through code, through PR, through the workflow. If an emergency manual change is needed, you import it into state or update the code to match, then run plan to verify.

---

## General Terraform Interview Questions (top 5)

### Q7: What is Terraform state and why is it important?

State is Terraform's record of what it has created. It maps your code to real resources. Without state, Terraform doesn't know what exists — it would try to create everything again. State tracks resource IDs, attributes, dependencies, and metadata. That's why remote state in S3 with locking is critical — if two people run apply at the same time without locking, they corrupt the state.

### Q8: What is the difference between `terraform plan` and `terraform apply`?

Plan is a dry run — it reads the code, reads the state, compares them, and shows what would change. Nothing is created or destroyed. Apply executes the changes. In my workflow, plan runs first and the output is reviewed before apply triggers. They're separate steps with a gate between them.

### Q9: What is state locking and what happens if the state gets corrupted?

State locking prevents two concurrent operations from writing to state at the same time. I use DynamoDB for this — when `terraform apply` starts, it writes a lock entry to DynamoDB. If another apply tries to run, it sees the lock and waits or fails.

If the state gets corrupted — I haven't faced this, but the approach is: first, don't panic and don't run apply. Pull the state with `terraform state pull`, inspect it. If it's a lock stuck from a crashed run, force-unlock with `terraform force-unlock <LOCK_ID>`. If the state file itself is damaged, restore from S3 versioning — that's why S3 bucket versioning should be enabled, you can roll back to the last good state. Worst case, if state is completely lost, you rebuild it by importing existing resources with `terraform import` one by one.

> Key signal: mention S3 versioning as your safety net. Most candidates don't think about state backup — they only think about locking.

### Q10: What is the difference between `terraform taint` and `terraform destroy`?

Taint marks a single resource for recreation on the next apply — it gets destroyed and recreated. Destroy tears down everything in the state (or a targeted resource with `-target`). In newer Terraform versions, `taint` is replaced by `terraform apply -replace=<resource>` which does the same thing more explicitly.

> When would you use it: if a VM is in a bad state and you want Terraform to rebuild it without touching anything else.

### Q11: What are data sources in Terraform?

Data sources read existing resources that Terraform doesn't manage. For example, looking up an AMI ID by filter, or reading an existing VPC to get its CIDR. They don't create anything — they just query. I use them in AWS to reference things like the OIDC provider ARN or existing account IDs.

---

## AWS-specific (from CV claims)

### Q12: Explain your OIDC federation setup between GitHub Actions and AWS.

GitHub Actions has an OIDC identity provider. I registered it in AWS as an OIDC provider via CloudFormation. When a workflow runs, GitHub issues a JWT token. The workflow calls `aws-actions/configure-aws-credentials` which exchanges that JWT for temporary STS credentials by assuming a role. The role's trust policy only allows the specific repo and branch — so the prod role only accepts tokens from the main branch, dev role only from dev branch. No static AWS keys stored anywhere in GitHub.

> This is a strong answer because it shows: zero static credentials, branch-scoped trust, STS short-lived tokens. If they ask "why not just use access keys?" — "because keys don't expire, can't be branch-scoped, and if leaked they give permanent access."

### Q13: Do you use Terraform workspaces? Why or why not?

No. Workspaces are Terraform's built-in way to manage multiple environments with the same code but different state files. I use separate folders instead — `terraform/dev/` and `terraform/prod/`. The reason: workspaces share the same code and can't drift independently. With separate folders, I can iterate freely on dev without any risk to prod, and I can allow intentional drift between environments. Separate folders is actually the recommended pattern for real prod/dev separation.

> If pushed: "Workspaces are fine for lightweight differences like testing a feature. For real environment separation where dev and prod might diverge intentionally, separate directories are safer."

### Q14: How do you bring existing resources under Terraform management?

`terraform import <resource_address> <resource_id>`. For example, `terraform import aws_instance.myvm i-1234567`. This adds the existing resource to the state file so Terraform can manage it going forward. After import, you write the matching resource block in code, then run `terraform plan` to verify there's no diff. If there is, you adjust the code until plan shows no changes.

> When would you use it: someone created a resource manually via console, or you're migrating from manual infrastructure to IaC.

### Q15: What are lifecycle rules in Terraform?

Lifecycle blocks control how Terraform handles resource changes. Three main ones:

- `prevent_destroy` — Terraform refuses to destroy this resource even if the code says so. Safety net for critical resources. I use this on some Proxmox resources to prevent accidental deletion.
- `create_before_destroy` — creates the replacement before destroying the old one. Useful for zero-downtime replacements.
- `ignore_changes` — tells Terraform to ignore changes to specific attributes. Useful when something is managed outside Terraform (like auto-scaling tags) and you don't want plan to show drift.

### Q16: What are provisioners and why are they discouraged?

Provisioners are blocks inside a resource that run scripts after creation — `remote-exec` runs commands on the remote machine, `local-exec` runs commands locally. HashiCorp discourages them because they're fragile, not declarative, and if they fail you're left in a half-configured state that Terraform can't track. The recommended approach is to use a proper configuration management tool. That's exactly what I do — Terraform provisions the resources, Ansible configures them after.

### Q17: What do `terraform validate` and `terraform fmt` do?

`terraform validate` checks whether the configuration is syntactically valid and internally consistent — missing required arguments, wrong types, bad references. It doesn't call any provider API, so it's fast and offline. `terraform fmt` rewrites the code into the canonical HCL style — consistent indentation, alignment, ordering. I run both locally before pushing. In my workflow: fmt → validate → plan locally on dev → push → CI runs plan + gated apply.

### Q18: How do you handle Terraform in a team environment?

Remote state in S3 so everyone reads the same state. DynamoDB locking so two people can't apply at the same time. All changes go through PRs — no one runs `terraform apply` from their laptop against prod. The CI workflow runs plan on PR, the output is reviewed, and apply only triggers after merge. Branch-scoped IAM roles mean the dev workflow can't touch prod resources. That's my setup today — even though I'm the only operator, the workflow enforces team-safe patterns.

> Key signal: "I built it for a team even though I'm solo" shows engineering maturity. The patterns are already there for day one at a real company.

### Q19: What is `depends_on` in Terraform?

Explicit dependency declaration between resources when Terraform can't infer it from references. Normally Terraform figures out the order from variable references — if resource B uses resource A's output, it knows to create A first. But sometimes there's a hidden dependency that isn't in the code — like a policy that must exist before a role can use it, but they don't reference each other directly. `depends_on` forces the ordering.

> Use it sparingly. If you need it everywhere, your code structure probably needs refactoring.

### Q20: What is `.terraform.lock.hcl`?

The dependency lock file. It records the exact provider versions and their hashes after `terraform init`. It ensures everyone on the team — and CI — uses the exact same provider binary, not just the same version constraint. You commit it to Git. This ties into my provider mirror setup — the lock file guarantees the mirrored provider matches what was tested locally.
