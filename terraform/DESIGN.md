# Terraform layer — design notes and reasoning

How the Terraform side of this project is structured, and why. Reads as a narrative, not a runbook — for the folder layout, versions, and quick start see [`README.md`](README.md).

---

## Why I kept dev and prod as two fully separate folders

I chose to mirror the same pattern used everywhere else in this repo (`ansible/`, `kubernetes/`, `.github/workflows/`): `terraform/dev/` and `terraform/prod/` are **two independent trees**, not one shared codebase driven by `-var env=dev|prod`, not Terraform workspaces, not a module with an env input.

My reasoning was very practical:

- I knew drifts between dev and prod would happen — and happen often, especially while learning the tools and iterating on the architecture.
- I wanted the freedom to apply a change on dev **without being forced to also apply it on prod**, and to run tests on dev that don't touch prod at all.
- A shared-var or workspace approach makes that hard. Every dev iteration becomes one step from also rolling into prod, every test needs a guard condition, every divergence has to be encoded as conditional logic inside the HCL itself.
- Keeping two independent trees means any drift is visible as a plain file diff. Nothing hidden inside `count = var.env == "prod" ? 1 : 0` or similar.

**Trade-off:** duplication. The two trees carry a lot of the same HCL, and I mirror changes manually — usually dev-first, then a mirror pass to prod with the env-specific tokens swapped (subnets 60s → 50s, CIDRs 172.16 → 172.17, region us-east-1 → eu-west-2, state bucket names, etc.).

To be clear about what this is: **two parallel trees is not the production pattern.** A mature team would write one shared module and drive it with `-var env=...` or Terraform workspaces, and that shared shape is the right answer once the architecture is settled. But for a learning-iteration phase, I've found it better to start with the simpler, more explicit approach first and let the shared-module abstraction emerge later — once I actually know where the patterns of divergence are. Abstracting too early, before you know which things will actually differ per env, produces the wrong abstraction and then fights you for the rest of the project. Starting concrete and refactoring to DRY later is cheaper than the reverse.

**You will see intentional sizing drift** between the two trees — k8s master CPU, worker memory, FreeIPA memory, Vault memory. Those are deliberate tier differences (prod hardware has more capacity, runs heavier workloads) not unmirrored drift. The `# Increased from 2048 to prevent control plane memory exhaustion` comment on dev's `k8s_masters/variables.tf` is dev-specific — prod is already over the "minimum recommended master memory" threshold, so that exhaustion context doesn't apply there.

---

## Why Terraform provisions, Ansible configures — and why Vault is on the Ansible side

I considered using Terraform's `vault` provider to manage HashiCorp Vault itself — policies, auth methods, roles, secrets engines, all as Terraform code. I decided against it **for the current project phase**.

The reasons:

- HashiCorp Vault is already deployed and configured by Ansible playbooks at [`../ansible/*/playbooks/vault/`](../ansible/). That path works and is tested.
- Putting Terraform in front of Vault would stack two tools through the same path: Ansible installs Vault → Terraform configures Vault's internals. I didn't want that coupling yet.
- The payoff (policy-as-code) isn't needed right now — the policy set is still evolving and is small enough to review inline in the Ansible templates.
- Adopting the Terraform Vault provider later is clean work — it can import existing state.

**Current split:**

| Layer | Tool | Where |
|-------|------|-------|
| Vault host LXCs + storage + network | **Terraform** | `proxmox/lxc/vault_cluster/` |
| AWS-side Vault dependencies (KMS auto-unseal, Vault-trust IAM) | **Terraform** | `aws/kms-vault-unseal/`, `aws/vault-trust/` |
| Vault install + cluster init + TLS + policies + engines | **Ansible** | `../ansible/*/playbooks/vault/` |

Same philosophy applies elsewhere:

- **K8s node provisioning** = Terraform (`proxmox/vms/k8s_masters/`, `k8s_workers/`).
- **K8s cluster bootstrap + workloads** = Ansible (`kubeadm init`) + Flux GitOps (everything on top).
- **FreeIPA host** = Terraform (`proxmox/vms/freeipa/`).
- **FreeIPA domain config + users + HBAC** = Ansible (`../ansible/*/playbooks/freeipa/`).

---

## What Terraform does NOT manage here

- **AWS bootstrap** (OIDC provider, TerraformAdmin role, S3 state bucket, DynamoDB lock, permissions boundary) — managed by CloudFormation, one-shot per account. See [`../aws/bootstrap.md`](../aws/bootstrap.md). That layer deliberately exists *outside* Terraform as a privilege-escalation fence.
- **HashiCorp Vault internal config** — Ansible, for reasons above.
- **Kubernetes workloads** — Flux CD (GitOps). See [`../kubernetes/`](../kubernetes/).
- **Node-level config after provisioning** — Ansible. See [`../ansible/`](../ansible/).

---

## IAM model (2-tier, with branch scoping) — brief pointer

Every AWS workflow in this repo authenticates via OIDC — **no long-lived AWS keys anywhere**. OIDC federation lets each workflow assume one of two IAM roles scoped by branch:

| Role | Scope | Branch trigger |
|------|-------|----------------|
| `GitHubActions-TerraformAdmin-{env}` | Admin + `PermissionsBoundary` — used for IAM, KMS, Vault-trust changes | `{env}-security` |
| `GitHubActions-Infrastructure-{env}` | `PowerUserAccess` + `SecurityBoundary` (no IAM mutation) — everything else | `{env}` |

Full reasoning — including why this tier split exists and where the `dev-security` / `prod-security` branch pattern actually came from — is in [`../aws/bootstrap.md`](../aws/bootstrap.md) (or [`../aws/DESIGN.md`](../aws/DESIGN.md) once split) under "Why this architecture". I'm not duplicating it here; that doc is the source of truth.

The `aws/iam/` module in *this* folder is where the `Infrastructure-{env}` role itself gets defined — via Terraform, running under the `TerraformAdmin-{env}` role that CloudFormation put in place.
