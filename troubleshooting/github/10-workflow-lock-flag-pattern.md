# GitHub Actions Workflow Lock Flag Pattern

## Problem

Terraform workflows triggered on push can accidentally destroy or recreate resources when:
- Making small edits to terraform files
- Pushing unrelated changes that match workflow paths
- Golden image templates being recreated after manual setup

## Solution

Use **repository variables** as lock flags to disable push triggers while allowing manual runs.

## Implementation

### 1. Add condition to workflow job

```yaml
jobs:
  create-vm:
    name: "Create VM"
    runs-on: mac-mini
    # Skip if locked (unless manual trigger)
    if: ${{ github.event_name == 'workflow_dispatch' || vars.WORKFLOW_LOCKED != 'true' }}
```

### 2. Create repository variable

1. Go to: **Settings → Secrets and variables → Actions → Variables tab**
2. Click **"New repository variable"**
3. Name: `WORKFLOW_LOCKED` (or specific name like `GOLDEN_IMAGE_DEV_LOCKED`)
4. Value: `true`

### How it works

| Trigger | Variable Value | Job Runs? |
|---------|----------------|-----------|
| Push | not set | Yes |
| Push | `false` | Yes |
| Push | `true` | **No (skipped)** |
| Manual (workflow_dispatch) | any | Yes |

### Current lock variables

| Workflow | Variable Name |
|----------|---------------|
| dev-proxmox-golden-image | `GOLDEN_IMAGE_DEV_LOCKED` |
| dev-proxmox-test-clones | `TEST_CLONES_DEV_LOCKED` |

## Usage

### Lock workflow (after setup complete)
- Set variable to `true`
- Push triggers will be skipped
- Manual "Run workflow" button still works

### Unlock workflow (need to make changes)
- Set variable to `false` or delete it
- Push triggers will run again

## Related

- [07-secrets-deletion-incident.md](./07-secrets-deletion-incident.md) - Incident that led to implementing approval gates
- Review windows (sleep delays) provide additional safety but don't prevent the workflow from starting

## Date Recorded
2026-02-16
