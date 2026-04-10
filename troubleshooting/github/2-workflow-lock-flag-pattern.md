# TS-GH-002 | 2026-03 | RESOLVED

## 1. Context
- System: GitHub Actions workflows
- Environment: Terraform automation for Proxmox infrastructure
- Related components: Golden image templates, test clone workflows, repository variables

## 2. Issue
- Symptom: Terraform workflows triggered on push accidentally destroy or recreate resources
- Error:
```
# Golden image template recreated after manual post-setup
# Resources destroyed due to unrelated file changes matching workflow paths
```

**Scenarios causing problems:**
- Making small edits to terraform files triggers full apply
- Pushing unrelated changes that match workflow path filters
- Golden image templates being recreated after manual setup (DNS, packages, etc.)

## 3. Analysis

**Check 1: Why are workflows running unexpectedly?**
```yaml
on:
  push:
    paths:
      - 'terraform/dev/**'
```
Finding: Any push matching paths triggers workflow - no way to "pause" after initial setup.

**Check 2: Can we stop push triggers but allow manual runs?**
```
workflow_dispatch always works
Need a way to conditionally skip push triggers
GitHub Actions supports repository variables in conditions
```
Finding: Repository variables can act as feature flags in workflow conditions.

## 4. Root Cause
> No mechanism to "lock" workflows after initial infrastructure setup. Push triggers run unconditionally when path filters match, risking destruction of manually configured resources.

## 5. Solution
> Use repository variables as lock flags to disable push triggers while allowing manual runs.

**Location:** GitHub repository settings + workflow files

**Step 1: Add condition to workflow job**

File: `.github/workflows/<workflow>.yml`
```yaml
jobs:
  create-vm:
    name: "Create VM"
    runs-on: mac-mini
    # Skip if locked (unless manual trigger)
    if: ${{ github.event_name == 'workflow_dispatch' || vars.WORKFLOW_LOCKED != 'true' }}
```

**Step 2: Create repository variable**
1. Go to: **Settings → Secrets and variables → Actions → Variables tab**
2. Click **"New repository variable"**
3. Name: `WORKFLOW_LOCKED` (or specific name like `GOLDEN_IMAGE_DEV_LOCKED`)
4. Value: `true`

**How it works:**

| Trigger | Variable Value | Job Runs? |
|---------|----------------|-----------|
| Push | not set | Yes |
| Push | `false` | Yes |
| Push | `true` | **No (skipped)** |
| Manual (workflow_dispatch) | any | Yes |

**Current lock variables:**

| Workflow | Variable Name |
|----------|---------------|
| dev-proxmox-golden-image | `GOLDEN_IMAGE_DEV_LOCKED` |
| dev-proxmox-test-clones | `TEST_CLONES_DEV_LOCKED` |

## 6. Solution Risk
- Risk level: LOW
- Potential impact: None - variable only affects job execution decision

## 7. Impact After Fix
- Observed: Push triggers skipped when locked, manual runs always work
- Golden images protected after initial setup
- No accidental resource recreation

## 8. Notes

**Usage:**
- **Lock workflow (after setup complete):** Set variable to `true` - push triggers skipped
- **Unlock workflow (need changes):** Set variable to `false` or delete it - push triggers run again

**Related:** TS-TF-002 (AWS secrets deletion incident in terraform/) led to implementing approval gates as additional safety measure.

## 9. Workaround (if any)
> Review windows (sleep delays) provide additional safety but don't prevent the workflow from starting. The lock flag pattern is the proper solution.
