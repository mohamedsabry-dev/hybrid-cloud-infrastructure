# TS-GH-002 | 2026-03 | RESOLVED
_____________________________________________________________________

[Info]
Domain: GitHub Actions
Sub-techs: Terraform workflows, repository variables, workflow conditions, workflow_dispatch
Environment: DEV | Proxmox infrastructure automation
Re-opened: No

_____________________________________________________________________

[Issue Description]
Terraform workflows triggered on push accidentally destroy or recreate resources.
No mechanism to pause push triggers after initial infrastructure setup is complete.

Scenarios causing problems:
  - Small edits to terraform files trigger full apply unexpectedly
  - Unrelated file changes match workflow path filters and kick off runs
  - Golden image templates recreated after manual post-setup (DNS, packages, etc.)

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Checked how workflows were being triggered and whether there was a way to pause them.

Workflow trigger config:
  on:
    push:
      paths:
        - 'terraform/dev/**'

Any push matching the path filter triggers the workflow — no conditional skip,
no way to pause after initial setup without removing the trigger entirely.

Checked if GitHub Actions supports conditional execution based on repository variables:

  workflow_dispatch always works regardless of conditions.
  Repository variables can be referenced in job if: conditions.
  This can act as a feature flag — lock flag pattern.


# Suspected Root Cause
No lock mechanism on push-triggered workflows. Once infrastructure is set up and
manually configured, any matching push risks triggering a full apply that overwrites
or recreates resources. Push triggers run unconditionally when path filters match.


# More Checks Notes:
N/A — GitHub Actions behavior confirmed from docs and testing.


# Suspected Solution
Use a repository variable as a lock flag in the job condition.
Push triggers check the variable — if locked, job is skipped.
Manual runs (workflow_dispatch) always bypass the lock.


# Test
Added condition to workflow job, created GOLDEN_IMAGE_DEV_LOCKED variable set to true,
pushed a change matching the path filter.

Result: PASS — push trigger skipped when locked, manual run executed normally.

_____________________________________________________________________

[Final Root Cause]
Push-triggered workflows had no conditional skip mechanism. After initial
infrastructure setup, any file change matching the path filter would trigger
a full Terraform apply risking destruction or recreation of manually configured
resources like golden image templates.

_____________________________________________________________________

[Final Solution]
Added repository variable lock flag pattern to all affected workflows.

Job condition in .github/workflows/<workflow>.yml:
  jobs:
    create-vm:
      if: ${{ github.event_name == 'workflow_dispatch' || vars.WORKFLOW_LOCKED != 'true' }}

Behavior:
  Push + variable not set  → runs
  Push + variable = false  → runs
  Push + variable = true   → skipped
  Manual trigger (any)     → always runs

To lock:   Settings → Secrets and variables → Actions → Variables → set to true
To unlock: set to false or delete the variable

Current lock variables:
  dev-proxmox-golden-image  → GOLDEN_IMAGE_DEV_LOCKED
  dev-proxmox-test-clones   → TEST_CLONES_DEV_LOCKED

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Variable only affects job execution decision. No infrastructure impact.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Related: TS-TF-002 — AWS secrets deletion incident in terraform/ led to
implementing approval gates as an additional safety layer on top of this.

Sleep delays in workflows provide a review window but do not prevent the
workflow from starting — lock flag is the proper solution for this.