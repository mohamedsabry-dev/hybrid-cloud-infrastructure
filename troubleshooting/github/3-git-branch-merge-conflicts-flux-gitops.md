# Case 3: Git Branch Merge Conflicts with Flux GitOps Multi-Environment Setup

## Problem Statement
After Flux bootstrap on prod cluster created commits directly to the prod branch, merging prod→dev to sync those files caused a cascading series of merge conflicts. The git history became a "spaghetti tree" with constant conflicts between dev and prod branches.

## Environment
- Repository: hybrid-cloud-infrastructure
- Branches: dev, prod (separate branches for separate AWS accounts)
- CI/CD: GitHub Actions with branch-based AWS assume roles
- GitOps: Flux CD on both dev and prod K8s clusters

## Project Design

### Intended Structure
```
Repository
├── dev branch
│   ├── terraform/dev/
│   ├── ansible/dev/
│   └── kubernetes/dev/
│       ├── flux/
│       └── deployments/
│
└── prod branch
    ├── terraform/prod/
    ├── ansible/prod/
    └── kubernetes/prod/
        ├── flux/
        └── deployments/
```

### Intended Workflow
1. Develop and test changes in dev branch
2. Copy working configs to prod folder (with prod-specific IPs/values)
3. PR dev → prod to deploy to production
4. Branch-based GitHub Actions trigger appropriate AWS account

## What Went Wrong

### The Trigger
1. Flux was bootstrapped on prod cluster
2. Flux bootstrap creates commits directly to the watched branch (prod)
3. These commits added `kubernetes/prod/flux/` manifests to prod branch

### The Mistake
To get the Flux manifests into dev branch for editing/testing:
```
prod → dev (WRONG DIRECTION)
```

This created a two-way merge flow:
```
dev ◄──────────────────► prod
      TWO-WAY MERGE
      = CONFLICTS
```

### The Cascade
1. Merged prod → dev to get Flux files
2. Edited Flux configs in dev
3. PR'd dev → prod
4. Conflicts on kustomization.yaml and other shared files
5. Resolved conflicts (sometimes incorrectly - conflict markers left in files)
6. More merges, more conflicts
7. Git history became unmanageable

### Symptoms
- Kustomize build errors: `yaml: line 6: could not find expected ':'`
- Conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`) left in YAML files
- Flux failing to reconcile
- 50+ files showing as changed in PRs
- Complex merge graph with many parallel lines

## Root Cause
**Two-way merging between environment branches that contain environment-specific content.**

When both branches have:
- Same folder structure (`kubernetes/*/deployments/`)
- Different content (dev IPs vs prod IPs)
- Commits happening on both branches independently

Merging in BOTH directions causes Git to repeatedly try to reconcile files that are intentionally different.

## Solution

### Immediate Fix
Reset prod branch to match dev exactly, then re-apply prod-specific changes:
```bash
git checkout prod
git reset --hard origin/dev
git push origin prod --force
```

### Correct Workflow

**Golden Rule: ONE-WAY FLOW ONLY**

```
dev ══════════════════════════════════► prod
              ONE WAY (PR)
              NEVER MERGE BACK
```

## Prevention Guidelines

### 1. Never Merge Prod → Dev
Even if prod has changes you need in dev:
- DON'T: `git merge prod` (while on dev)
- DON'T: PR prod → dev
- DO: Manually recreate the changes in dev branch

### 2. Flux Bootstrap Procedure
When bootstrapping Flux on a new environment:

**Option A: Bootstrap on dev first (Recommended)**
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

**Option B: If already bootstrapped on prod**
```bash
# Don't merge! Instead, manually copy structure to dev
# On dev branch:
mkdir -p kubernetes/dev/flux
# Recreate the flux structure based on prod, with dev values
```

### 3. Environment-Specific Values
Keep environment differences in clearly separated files:
```
kubernetes/
├── dev/
│   └── deployments/
│       └── infrastructure/
│           └── storage/
│               └── nfs-pv.yaml  # dev IPs: 10.0.40.201-203
└── prod/
    └── deployments/
        └── infrastructure/
            └── storage/
                └── nfs-pv.yaml  # prod IPs: 10.0.40.101-103
```

### 4. Branch Protection
Enable branch protection on prod:
- Require PR reviews
- Require status checks
- Block force push (except for emergencies)

### 5. Clean Commit Messages
When copying from dev to prod, use clear commit messages:
```
Mirror ansible/dev/playbooks/k8s/worker-nfs-mount.yml to prod

- Copied from dev branch
- Updated IPs for prod environment
- Updated mount path to /volume1/k8s-prod
```

## Workflow Diagram

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

## Recovery Steps (If It Happens Again)

### 1. Check for Conflict Markers
```bash
# Find files with unresolved conflict markers
grep -r "<<<<<<" kubernetes/ terraform/ ansible/
grep -r "======" kubernetes/ terraform/ ansible/
grep -r ">>>>>>" kubernetes/ terraform/ ansible/
```

### 2. Reset Prod to Dev (Nuclear Option)
```bash
# Disable branch protection first
git checkout prod
git reset --hard origin/dev
git push origin prod --force
# Re-enable branch protection
```

### 3. Reapply Prod-Specific Changes
After reset, manually update prod-specific values in the prod folders.

## Lessons Learned

1. **Design branching strategy BEFORE starting** - Understand how branches will interact
2. **One-way flow for environment branches** - Source (dev) → Target (prod) only
3. **Bootstrap GitOps tools on source branch first** - Copy to other environments
4. **Conflict markers break YAML** - Always verify merge results
5. **Branch protection prevents accidents** - But allow emergency force push for admins
6. **Git reflog is your friend** - Can always recover from mistakes

## Related Files
- kubernetes/dev/flux/
- kubernetes/prod/flux/
- kubernetes/*/deployments/kustomization.yaml

## Date
2026-03-28
