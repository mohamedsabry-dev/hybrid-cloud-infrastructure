# TS-AWS-001 | 2026-01-30 | RESOLVED
_____________________________________________________________________

[Info]
Domain: AWS
Sub-techs: CloudFormation, IAM Managed Policy
Environment: Stack hybrid-policies | Resource SecurityAuditControlPolicy | Policy HybridCloud-SecurityAuditControl
Re-opened: No

_____________________________________________________________________

[Issue Description]
Stack update failed when modifying IAM policy via CloudFormation.

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Tried to update a CloudFormation stack with two changes at once — the policy description and the policy document (adding new permissions).

Changes intended:
  # Triggers REPLACEMENT
  Description: "Security and audit infrastructure management"
  → Description: "Security, audit, and monitoring infrastructure management"

  # In-place UPDATE (safe)
  PolicyDocument:
    - Added: ManageCloudWatchAlarms
    - Added: ManageEventBridge
    - Added: ManageSNSForAlarms

Stack failed mid-way with:
  "A policy called HybridCloud-SecurityAuditControl already exists.
   Duplicate names are not allowed. (Service: Iam, Status Code: 409)"

  UPDATE_IN_PROGRESS → "Requested update requires the creation of a new physical resource"
  UPDATE_FAILED      → "Duplicate names are not allowed"

Expected behavior was either an in-place update or a destroy-then-create — same analogy as updating a value in a database. What I figured out is that changing the Description on an IAM Managed Policy is not a simple edit from AWS perspective. AWS treats it as destroy the old resource and create a new one. I expected this to work like Terraform (delete first, then create), but CloudFormation's strategy is the opposite — create new first, then delete old. That conflicts with an explicitly named policy since the old one is still there when CloudFormation tries to create the new one.

Check: Which IAM Managed Policy properties are immutable?

  Property          | Mutable? | Update Type
  ------------------|----------|------------------
  PolicyDocument    | Yes      | In-place update
  Description       | No       | Requires replacement
  ManagedPolicyName | No       | Requires replacement
  Path              | No       | Requires replacement

Confirmed via AWS Console — there is no edit option for Description at all.

Output:
  CloudFormation replacement flow for named resource:
    1. Create NEW policy "HybridCloud-SecurityAuditControl"  → FAILS: name already exists
    2. Update references                                     → never reached
    3. Delete OLD policy                                     → never reached


# Suspected Root Cause
Description is immutable on IAM Managed Policy. Changing it triggers resource replacement. CloudFormation uses create-before-delete strategy, which fails when an explicit name is used — the old policy is still alive when CloudFormation tries to create the new one with the same name.


# More Checks Notes:
Verified via AWS Console that Description field has no edit option — replacement behavior confirmed.

Command: AWS Console → IAM → Policies → HybridCloud-SecurityAuditControl

Output: No edit option visible for Description field. Immutability confirmed at console level.


# Suspected Solution
Revert the Description change. Keep only the PolicyDocument changes since those are in-place updates and safe to apply.


# Test
Reverted Description to original value and re-applied the stack update with only PolicyDocument changes.

Result: PASS — stack updated successfully, policy has the new statements.

_____________________________________________________________________

[Final Root Cause]
IAM Managed Policy Description is immutable after creation. Changing it triggers CloudFormation to replace the resource using its create-before-delete strategy. Since the policy has an explicit name, CloudFormation cannot create the replacement — a policy with that name already exists and AWS returns 409. Stack gets stuck mid-update.

_____________________________________________________________________

[Final Solution]
Reverted Description to its original value. Applied only the PolicyDocument changes, which are in-place updates and do not require resource replacement. Stack updated cleanly.

  # Keep original — no replacement triggered
  Description: "Security and audit infrastructure management"

  # Safe to change — in-place update
  PolicyDocument:
    Added: ManageCloudWatchAlarms, ManageEventBridge, ManageSNSForAlarms

If changing Description/Name/Path is truly required:
  - Option 1: Delete the resource manually first, then update
  - Option 2: Remove the explicit name and let CloudFormation auto-generate
  - Option 3: Use Terraform with lifecycle { create_before_destroy = false }  ^_^

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: No impact — original description kept, policy functionality unchanged.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

CloudFormation vs Terraform replacement strategy:

  Aspect                   | CloudFormation          | Terraform
  -------------------------|-------------------------|----------------------------------
  Replacement strategy     | Fixed: create-then-delete | Configurable via lifecycle block
  Named resource handling  | Fails with duplicates   | create_before_destroy = false

Terraform equivalent if name change is needed:
  resource "aws_iam_policy" "security_audit" {
    name        = "HybridCloud-SecurityAuditControl"
    description = "Security and audit infrastructure management"
    policy      = jsonencode({...})

    lifecycle {
      create_before_destroy = false  # delete old first, then create new
    }
  }

Safe vs Unsafe changes on IAM Managed Policy:
  SAFE   → PolicyDocument (in-place, no replacement)
  UNSAFE → Description, ManagedPolicyName, Path (all trigger replacement, will fail with named policy)