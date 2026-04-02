# Case 1: CloudFormation IAM Policy Replacement Failure

## Status: RESOLVED
## Date: 2026-01-30
## Environment: CloudFormation Policy Update Failed with "Duplicate Name"
**Stack:** `hybrid-policies`
**Resource:** `SecurityAuditControlPolicy`

---

## The Error

```
Resource handler returned message: "A policy called HybridCloud-SecurityAuditControl
already exists. Duplicate names are not allowed. (Service: Iam, Status Code: 409)"
```

**Stack Event:**
```
UPDATE_IN_PROGRESS → "Requested update requires the creation of a new physical resource"
UPDATE_FAILED → "Duplicate names are not allowed"
```

---

## What We Changed

```yaml
# Changed (triggers REPLACEMENT)
Description: "Security and audit infrastructure management"
→ Description: "Security, audit, and monitoring infrastructure management"

# Changed (in-place UPDATE - safe)
PolicyDocument:
  - Added: ManageCloudWatchAlarms
  - Added: ManageEventBridge
  - Added: ManageSNSForAlarms
```

---

## Root Cause

| Property | Mutable? | Update Type |
|----------|----------|-------------|
| `PolicyDocument` | Yes | In-place update |
| `Description` | No | **Requires replacement** |
| `ManagedPolicyName` | No | Requires replacement |
| `Path` | No | Requires replacement |

**Key Finding:** IAM Managed Policy `Description` is **immutable** after creation.
AWS Console doesn't even show an edit option for it.

---

## Why CloudFormation Failed

CloudFormation uses **create-then-delete** replacement strategy:

```
1. Create NEW policy "HybridCloud-SecurityAuditControl"
   → FAILS: Name already exists (old policy still there)

2. Update references (never reached)

3. Delete OLD policy (never reached)
```

CloudFormation cannot create the new resource because the old one with the same name still exists.

---

## The Fix

**Reverted the Description change** - only kept `PolicyDocument` changes:

```yaml
# Keep original (no replacement needed)
Description: "Security and audit infrastructure management"

# Only change PolicyDocument (in-place update)
PolicyDocument:
  # ... new statements added
```

**Result:** Stack updated successfully.

---

## CloudFormation vs Terraform

| Aspect | CloudFormation | Terraform |
|--------|---------------|-----------|
| **Replacement Strategy** | Fixed: create-then-delete | Configurable via `lifecycle` |
| **Named Resource Handling** | Fails with duplicates | Can use `create_before_destroy = false` |
| **Dependency Management** | Basic | Full graph-based |
| **Preview Changes** | Change Sets (limited) | `terraform plan` (detailed) |

### Terraform Equivalent (with lifecycle control)

```hcl
resource "aws_iam_policy" "security_audit" {
  name        = "HybridCloud-SecurityAuditControl"
  description = "Security and audit infrastructure management"
  policy      = jsonencode({...})

  lifecycle {
    # Delete old first, then create new (avoids naming conflict)
    create_before_destroy = false
  }
}
```

---

## Lessons Learned

1. **Never change immutable properties** on named IAM resources:
   - `Description`
   - `ManagedPolicyName`
   - `Path`

2. **Only modify `PolicyDocument`** for in-place updates

3. **If replacement is needed:**
   - Manually delete the resource first, OR
   - Remove explicit name and let CloudFormation auto-generate, OR
   - Consider migrating to Terraform for better lifecycle control

4. **Test with Change Sets** before applying CloudFormation updates

---

## Quick Reference: Safe vs Unsafe Changes

```yaml
# SAFE - In-place update
PolicyDocument:
  Statement:
    - Sid: NewStatement  # Adding/modifying statements

# UNSAFE - Triggers replacement (will fail with named policies)
Description: "Changed description"
ManagedPolicyName: "NewName"
Path: "/new-path/"
```
