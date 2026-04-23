# TS-GH-008 | 2026-03-28 | RESOLVED
_____________________________________________________________________

[Info]
Domain: GitHub Actions / Git
Sub-techs: Git branching strategy, Flux CD bootstrap, merge conflicts, GitOps, Kustomize
Environment: Multi-environment (dev/prod branches, separate AWS accounts)
Re-opened: No

_____________________________________________________________________

[Issue Description]
After Flux bootstrap on prod cluster, merging prod→dev caused cascading merge
conflicts. Git history became a spaghetti tree with constant conflicts. Flux
failing to reconcile due to broken YAML — conflict markers accidentally left
in committed files.

  50+ files showing as changed in PRs
  Complex merge graph with many parallel lines
  Kustomize build errors: yaml: line 6: could not find expected ':'
  Conflict markers (<<<<<<, ======, >>>>>>) committed into YAML files

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Traced what triggered the conflict cascade.

Flux bootstrap on prod cluster creates commits directly to the prod branch.
To get Flux manifests into dev for editing, merged prod → dev.
This started a two-way merge flow between branches that have intentionally
different content (dev IPs vs prod IPs, dev paths vs prod paths).

Two-way merging means:
  dev ◄──────────────────► prod
  Both branches have same folder structure, different content.
  Git repeatedly tries to reconcile files that are intentionally different.
  Every merge in either direction produces conflicts.

Searched for conflict markers left in committed files:

Command:
  grep -r "<<<<<<" kubernetes/ terraform/ ansible/
  grep -r "======" kubernetes/ terraform/ ansible/
  grep -r ">>>>>>" kubernetes/ terraform/ ansible/

Output:
  Conflict markers found in multiple YAML files — Kustomize cannot parse them.


# Suspected Root Cause
Two-way merging between environment branches that hold environment-specific content.
Merging in both directions forces Git to repeatedly reconcile files that are
intentionally different by design. Conflict markers left in files broke Kustomize builds.


# More Checks Notes:
Confirmed the merge direction history — prod→dev merge was the starting point
that created the two-way flow. All subsequent conflicts traced back to that
initial wrong-direction merge.


# Suspected Solution
Establish one-way merge flow: dev→prod only, never prod→dev.
Reset prod branch to match dev, reapply prod-specific changes manually.
Fix YAML files with conflict markers before re-running Flux.


# Test
Reset prod to dev, reapplied prod-specific values, ran Flux reconciliation.

Command:
  grep -r "<<<<<<" kubernetes/ terraform/ ansible/
  flux reconcile kustomization flux-system

Result: PASS — no conflict markers, Flux reconciling cleanly, PRs showing only
actual changes.

_____________________________________________________________________

[Final Root Cause]
Flux bootstrap on prod created commits directly on the prod branch. To get those
manifests into dev, prod was merged into dev — creating a two-way merge flow.
Both branches share the same folder structure but have intentionally different
content (different IPs, paths, environments). Merging in both directions forces
Git to repeatedly reconcile files that should never be reconciled. Conflict markers
were left in YAML files and accidentally committed, breaking Kustomize builds.

_____________________________________________________________________

[Final Solution]
Immediate fix — reset prod to match dev, reapply prod-specific changes:

  # Disable branch protection first
  git checkout prod
  git reset --hard origin/dev
  git push origin prod --force
  # Re-enable branch protection
  # Manually reapply prod-specific values

One-way merge rule going forward:
  dev ══════════════════════════════════► prod
  ONE WAY via PR only — NEVER merge prod → dev

Golden rules:
  1. Never merge prod → dev under any circumstance
  2. If prod has something dev needs, recreate it manually in dev
  3. Bootstrap Flux on dev first, then copy manifests to prod folder

Correct Flux bootstrap procedure:
  # Bootstrap on dev cluster pointing to dev branch
  flux bootstrap github \
    --owner=<owner> \
    --repository=hybrid-cloud-infrastructure \
    --branch=dev \
    --path=kubernetes/dev/flux

  # Copy to prod folder manually
  cp -r kubernetes/dev/flux kubernetes/prod/flux
  # Update prod configs (branch, paths, IPs) then PR to prod

IMPORTANT — merge type matters for long-lived branches:
  Merge commit   → preserves hashes, Git tracks what is merged  ← USE THIS
  Squash merge   → creates new hashes, Git loses merge tracking  ← DO NOT USE
  Rebase merge   → rewrites hashes, same problem as squash       ← DO NOT USE

Repo settings required:
  Allow merge commits: ON
  Allow squash merging: OFF for dev→prod PRs
  Allow rebase merging: OFF for dev→prod PRs

See TS-GH-010 for details on squash/rebase merge issues with long-lived branches.

Verified: Yes

_____________________________________________________________________

[Risk Level] HIGH
Note: Force push to prod rewrites history. Disable branch protection before
running, coordinate with team, re-enable after.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Lessons learned:
  - Design branching strategy before starting, not after
  - One-way flow is mandatory for environment branches with different content
  - Bootstrap GitOps tools on source branch first, copy to others manually
  - Conflict markers in YAML are silent until Kustomize tries to build
  - Always grep for conflict markers before pushing: grep -r "<<<<<<" .
  - Git reflog can recover from mistakes if force push goes wrong

Commit message style when copying dev→prod:
  Mirror ansible/dev/playbooks/k8s/worker-nfs-mount.yml to prod
  - Copied from dev branch
  - Updated IPs for prod environment
  - Updated mount path to /volume1/k8s-prod

Minor conflict workaround:
  Resolve manually in favor of correct environment values.
  Verify with grep -r "<<<<<<" . before pushing.