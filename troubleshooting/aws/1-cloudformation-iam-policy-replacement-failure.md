# TS-AWS-001 | 2026-01-30 | RESOLVED

## 1. Context
- System: AWS CloudFormation
- Environment: Stack `hybrid-policies`, Resource `SecurityAuditControlPolicy`
- Related components: IAM Managed Policy `HybridCloud-SecurityAuditControl`

## 2. Issue
- Symptom: Stack update failed when modifying IAM policy
- Error:
```
Resource handler returned message: "A policy called HybridCloud-SecurityAuditControl
already exists. Duplicate names are not allowed. (Service: Iam, Status Code: 409)"

UPDATE_IN_PROGRESS → "Requested update requires the creation of a new physical resource"
UPDATE_FAILED → "Duplicate names are not allowed"
```

**What we changed:**
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

## 3. Analysis

**Check 1: Which IAM properties are immutable?**

| Property | Mutable? | Update Type |
|----------|----------|-------------|
| `PolicyDocument` | Yes | In-place update |
| `Description` | No | **Requires replacement** |
| `ManagedPolicyName` | No | Requires replacement |
| `Path` | No | Requires replacement |

AWS Console doesn't even show edit option for Description - confirmed immutable.

**Check 2: Why does CloudFormation replacement fail?**

CloudFormation uses create-then-delete strategy:
```
1. Create NEW policy "HybridCloud-SecurityAuditControl"
   → FAILS: Name already exists (old policy still there)
2. Update references (never reached)
3. Delete OLD policy (never reached)
```

Can't create new resource with same name while old one exists.

## 4. Root Cause
> IAM Managed Policy `Description` is immutable after creation. Changing it triggers resource replacement, but CloudFormation's create-then-delete strategy fails because a policy with the same name already exists.

## 5. Solution
> Revert Description change, only modify PolicyDocument (which updates in-place).

```yaml
# Keep original (no replacement needed)
Description: "Security and audit infrastructure management"

# Only change PolicyDocument (in-place update)
PolicyDocument:
  # ... new statements added
```

Result: Stack updated successfully.

## 6. Solution Risk
- Risk level: LOW
- Potential impact: None - just keeping original description

## 7. Impact After Fix
- Observed: Stack updated successfully, policy has new statements
- No new issues caused

## 8. Notes

**CloudFormation vs Terraform:**

| Aspect | CloudFormation | Terraform |
|--------|---------------|-----------|
| Replacement Strategy | Fixed: create-then-delete | Configurable via `lifecycle` |
| Named Resource Handling | Fails with duplicates | Can use `create_before_destroy = false` |

**Terraform equivalent with lifecycle control:**
```hcl
resource "aws_iam_policy" "security_audit" {
  name        = "HybridCloud-SecurityAuditControl"
  description = "Security and audit infrastructure management"
  policy      = jsonencode({...})

  lifecycle {
    create_before_destroy = false  # Delete old first, then create new
  }
}
```

**Safe vs Unsafe changes:**
```yaml
# SAFE - In-place update
PolicyDocument:
  Statement:
    - Sid: NewStatement

# UNSAFE - Triggers replacement (will fail with named policies)
Description: "Changed description"
ManagedPolicyName: "NewName"
Path: "/new-path/"
```

## 9. Workaround (if any)
> If you must change Description/Name/Path:
> 1. Manually delete the resource first, OR
> 2. Remove explicit name and let CloudFormation auto-generate, OR
> 3. Use Terraform with `create_before_destroy = false`
