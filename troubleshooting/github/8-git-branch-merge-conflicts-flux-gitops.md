# TS-GH-008 | 2026-03-28 | RESOLVED

## 1. Context
- System: Git branching / GitHub repository
- Environment: Multi-environment setup (dev/prod branches for separate AWS accounts)
- Related components: Flux CD GitOps, GitHub Actions, Kubernetes manifests

## 2. Issue
- Symptom: After Flux bootstrap on prod cluster, merging prod→dev caused cascading merge conflicts. Git history became "spaghetti tree" with constant conflicts.
- Error:
```
# Kustomize build errors
yaml: line 6: could not find expected ':'

# Conflict markers left in YAML files
<<<<<<< HEAD
=======
>>>>>>>
```

**Observed behavior:**
- 50+ files showing as changed in PRs
- Complex merge graph with many parallel lines
- Flux failing to reconcile due to broken YAML
- Conflict markers accidentally committed to files

## 3. Analysis

**Check 1: What triggered the problem?**
```
1. Flux bootstrap on prod cluster creates commits directly to prod branch
2. To get Flux manifests into dev for editing/testing, merged prod → dev
3. This created two-way merge flow
```
Finding: Wrong merge direction started the conflict cascade.

**Check 2: Why do conflicts keep appearing?**
```
dev ◄──────────────────► prod
      TWO-WAY MERGE
      = CONFLICTS

Both branches have:
- Same folder structure (kubernetes/*/deployments/)
- Different content (dev IPs vs prod IPs)
- Independent commits on both branches
```
Finding: Merging in BOTH directions causes Git to repeatedly reconcile intentionally different files.

**Check 3: Find conflict markers left in files**
```bash
grep -r "<<<<<<" kubernetes/ terraform/ ansible/
grep -r "======" kubernetes/ terraform/ ansible/
grep -r ">>>>>>" kubernetes/ terraform/ ansible/
```
Finding: Conflict markers left in multiple YAML files breaking Kustomize builds.

## 4. Root Cause
> Two-way merging between environment branches that contain environment-specific content. When merging in both directions, Git repeatedly tries to reconcile files that are intentionally different (dev IPs vs prod IPs).

## 5. Solution
> Establish one-way merge flow: dev → prod only. Never merge prod → dev.

**Immediate Fix: Reset prod to match dev**
```bash
# Disable branch protection first
git checkout prod
git reset --hard origin/dev
git push origin prod --force
# Re-enable branch protection
# Then reapply prod-specific changes
```

**Correct Workflow:**
```
dev ══════════════════════════════════► prod
              ONE WAY (PR)
              NEVER MERGE BACK
```

**Golden Rules:**
1. **Never merge prod → dev** - Even if prod has changes you need
2. **Manually recreate** - If prod has something dev needs, recreate it in dev
3. **Bootstrap on dev first** - Then copy to prod folders

**Flux Bootstrap Procedure (Correct Way):**
```bash
# Bootstrap Flux on dev cluster, pointing to dev branch
flux bootstrap github \
  --owner=mohamedsabry-dev \
  --repository=hybrid-cloud-infrastructure \
  --branch=dev \
  --path=kubernetes/dev/flux

# Copy flux manifests to prod folder
cp -r kubernetes/dev/flux kubernetes/prod/flux

# Update prod flux configs (branch, paths)
# Push to dev, PR to prod
```

**If already bootstrapped on prod (don't merge!):**
```bash
# On dev branch - manually copy structure
mkdir -p kubernetes/dev/flux
# Recreate the flux structure based on prod, with dev values
```

## 6. Solution Risk
- Risk level: HIGH (force push to prod)
- Potential impact: Force push rewrites history - coordinate with team, disable branch protection temporarily

## 7. Impact After Fix
- Observed: Clean merge history, no more conflicts
- PRs show only actual changes
- Flux reconciliation works correctly

## 8. Notes

**Workflow Diagram:**
```
┌─────────────────────────────────────────────────────────────┐
│                    CORRECT WORKFLOW                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   DEV BRANCH (Source of Truth)                              │
│   │                                                          │
│   ├── 1. Create new feature in terraform/dev/               │
│   ├── 2. Test on dev environment                            │
│   ├── 3. Copy to terraform/prod/ with prod values           │
│   ├── 4. Commit both changes                                │
│   └── 5. Push to dev branch                                 │
│           │                                                  │
│           ▼                                                  │
│   ┌───────────────┐                                         │
│   │  Pull Request │ (dev → prod)                            │
│   │  Review & Test│                                         │
│   └───────────────┘                                         │
│           │                                                  │
│           ▼                                                  │
│   PROD BRANCH (Receives from dev only)                      │
│   │                                                          │
│   └── GitHub Actions → AWS Prod Account                     │
│                                                              │
│   ═══════════════════════════════════════════════════════   │
│   ██ NEVER: prod → dev merge ██                             │
│   ═══════════════════════════════════════════════════════   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Commit message style when copying dev→prod:**
```
Mirror ansible/dev/playbooks/k8s/worker-nfs-mount.yml to prod

- Copied from dev branch
- Updated IPs for prod environment
- Updated mount path to /volume1/k8s-prod
```

**Lessons learned:**
1. Design branching strategy BEFORE starting
2. One-way flow for environment branches
3. Bootstrap GitOps tools on source branch first
4. Conflict markers break YAML - always verify merge results
5. Branch protection prevents accidents
6. Git reflog can recover from mistakes

## 9. Workaround (if any)
> If minor conflicts occur, carefully resolve in favor of the correct environment values. Use `git mergetool` or resolve manually, then verify with `grep -r "<<<<<<" .` before pushing.
