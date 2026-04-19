# GitHub Configuration

Documentation for how this repo uses GitHub — Actions workflows, self-hosted runners, secrets/variables, branch strategy, and the deployment flow. The workflow YAML files themselves live under [`../.github/workflows/`](../.github/workflows/); this folder explains the *why* and the *how we set it up*.

---

## Documents

| File | Description |
|------|-------------|
| [`deployment-flow.md`](deployment-flow.md) | Full end-to-end deploy order (workflows 1-11), boot order, SSH trust chain |
| [`deployment-pattern.md`](deployment-pattern.md) | Branch strategy (standard vs IAM/security paths) with reasoning |
| [`internal-runners-setup.md`](internal-runners-setup.md) | Self-hosted runner setup inside each env (dev / prod local-runner LXCs) |
| [`runner-mac-mini.md`](runner-mac-mini.md) | Mac Mini self-hosted runner — why self-hosted, tools, provider mirror |
| [`variables-secrets.md`](variables-secrets.md) | Full reference: repo secrets, vars, lock vars, AWS Secrets Manager paths, OIDC reasoning |

---

## Runner architecture

```
GitHub Actions
     │
     ├── mac-mini  (self-hosted, at my workstation)
     │   └── Terraform — talks to AWS, GitHub, Proxmox API from outside.
     │                   Has local provider mirror for fast init.
     │
     ├── {env}-local-runner  (self-hosted LXC, inside the workload network)
     │   └── Ansible — SSHes to Ansible LXC, which runs playbooks
     │                 against the internal fleet.
     │
     └── ubuntu-latest  (GitHub-hosted)
         └── Container image builds only (build-docker-images.yml → GHCR).
```

**No workflow uses GitHub-hosted runners for infrastructure.** Everything
infrastructure-related runs on one of the two self-hosted paths. The reason
for the split — mac-mini for outside-in work, local-runner for inside-out
work — is documented in [`runner-mac-mini.md`](runner-mac-mini.md) and
[`../deployment-docs/ansible-runner-setup-guide.txt`](../deployment-docs/ansible-runner-setup-guide.txt).

### Runner reference

| Runner | Location | Purpose |
|--------|----------|---------|
| `mac-mini` | Workstation (macOS ARM64) | Terraform (AWS + Proxmox), GH CLI |
| `dev-local-runner` | Proxmox LXC, 10.0.63.20 | Ansible playbooks against DEV fleet |
| `prod-local-runner` | Proxmox LXC, 10.0.53.20 | Ansible playbooks against PROD fleet |
| `ubuntu-latest` | GitHub-hosted | Docker image builds only |

---

## Branch strategy at a glance

Two paths, depending on what the change touches. Full reasoning is in
[`deployment-pattern.md`](deployment-pattern.md).

**Infrastructure changes** (VMs, LXCs, networking, Ansible playbooks, K8s manifests):
```
dev  →  prod  →  main
```

**IAM / Security changes** (AWS IAM, KMS, Vault trust):
```
dev  →  dev-security  →  prod-security  →  prod  →  main
```

The extra detour for IAM is deliberate — IAM bad changes have different
(and harder-to-revert) blast radius than infrastructure changes. Each
transition requires a reviewed PR.

### Branch roles

| Branch | Role | Workflows triggered on push |
|--------|------|------------------------------|
| `dev` | Active development | All `dev-*-full-setup.yml` (non-IAM) |
| `dev-security` | Dev IAM gate | `dev-aws-iam`, `dev-aws-kms-vault-unseal`, `dev-aws-vault-trust` |
| `prod` | Production infra | All `prod-*-full-setup.yml` (non-IAM) |
| `prod-security` | Prod IAM gate | `prod-aws-iam`, `prod-aws-kms-vault-unseal`, `prod-aws-vault-trust` |
| `main` | Clean merge target, no workflows | None — receives PRs from `prod` at milestone completion |

### Branch protection

| Branch | Merge approval | CI checks | Audit trail |
|--------|----------------|-----------|-------------|
| `main` | Required | Required | Enabled |
| `prod` | Required | Required | Enabled |
| `prod-security` | Required | — | Enabled |
| `dev-security` | Required | — | Enabled |
| `dev` | Not required | — | — |

---

## Troubleshooting

Real operational incidents I've hit around GitHub Actions, runners, and git history, documented under [`../troubleshooting/github/`](../troubleshooting/github/). Worth reading before / while setting things up here — a lot of them are the kind of bugs you can only understand *after* they've bitten you:

| # | File | Gist |
|---|------|------|
| 1 | `1-github-runner-stuck-job.md` | Runner stuck mid-job, how to safely recover |
| 2 | `2-workflow-lock-flag-pattern.md` | The lock-variable pattern used across all `{env}-*-full-setup.yml` |
| 3 | `3-delete-workflow-logs-secrets.md` | How to delete workflow logs that captured secrets |
| 4 | `4-git-history-secrets-cleanup.md` | Scrubbing secrets from git history cleanly |
| 5 | `5-runner-clock-skew-auth-failure.md` | GH runner auth failing because of host clock skew |
| 6 | `6-mac-address-deep-inspection-cleanup.md` | MAC-address-based GH session conflict cleanup |
| 7 | `7-concurrent-terraform-workflow-lxc-reboot.md` | Two Terraform workflows racing on the same LXC |
| 8 | `8-git-branch-merge-conflicts-flux-gitops.md` | Merge conflict patterns in a Flux/GitOps setup |
| 9 | `9-commit-attributed-to-wrong-user.md` | Commits landing under the wrong Git identity |
| 10 | `10-squash-merge-causes-recurring-conflicts.md` | Why squash-merge caused recurring conflicts in this repo (part of why commits are not squashed — see root project notes) |

If you are setting this up from scratch, skim cases 2, 5, and 7 first — they cover the patterns you will hit earliest.

---

## Related

- [`../.github/workflows/`](../.github/workflows/) — the actual workflow YAML files
- [`../.github/workflows/README.md`](../.github/workflows/README.md) — workflow conventions (lock vars, OIDC, always-pattern, secret masking)
- [`../.github/workflows/workflow-guide.txt`](../.github/workflows/workflow-guide.txt) — how to write a new workflow
- [`../deployment-docs/`](../deployment-docs/) — per-service setup guides (freeipa, vault, k8s, ansible/runner)
- [`../troubleshooting/github/`](../troubleshooting/github/) — 10 real operational cases (see section above)
