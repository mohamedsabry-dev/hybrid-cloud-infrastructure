# TS-TF-002 | 2026-02-14 | RESOLVED

## 1. Context
- System: Terraform with AWS Secrets Manager
- Environment: AWS Dev Account (eu-west-2)
- Related components: S3 state backend, DynamoDB lock table, GitHub Actions workflow

## 2. Issue
- Symptom: Terraform workflow accidentally scheduled deletion of all AWS Secrets Manager secrets. State file corrupted to 299 bytes (normally 14KB).
- Error:
```
# State checksum mismatch
S3 checksum:      47f5e65e55b95a3605ffc0cd496960d7
DynamoDB checksum: ae0fd0e5a2f149fb1f7ffc54d85a9507
```

**Timeline:**
- Feb 12 ~8:00 PM: Made "small name change" to Terraform secrets config
- Workflow triggered, noticed destroy in plan, canceled workflow
- Feb 14 10:00 AM: Discovered all secrets missing from AWS Console
- State file only 299 bytes, secrets scheduled for deletion

## 3. Analysis

**Check 1: What caused the deletion?**
```
Terraform name change triggered resource replacement:
- Old resource: DELETE
- New resource: CREATE
- Workflow canceled mid-execution
- State partially updated
```
Finding: Secrets entered deletion queue despite workflow cancellation.

**Check 2: Why is state file corrupted?**
```bash
# Normal state size: 14.0 KB (14,336 bytes)
# Corrupted state size: 299 bytes
# Size reduction: 98%
```
Finding: State file corruption mechanism unclear - possibly mid-write cancellation.

**Check 3: Can secrets be recovered?**
```
AWS Secrets Manager deletion window: 7-30 days
Secrets found in AWS Console as "scheduled for deletion"
```
Finding: All secrets recoverable before deletion window expires.

## 4. Root Cause
> No approval gate between terraform plan and apply. Workflow cancellation occurred after state update committed, leaving secrets scheduled for deletion and state corrupted. Contributing factors: automatic workflow trigger on push, limited time to review plan output.

## 5. Solution
> Restore secrets from deletion queue, fix state checksum, implement approval gate.

**Location:** AWS Console + DynamoDB + Terraform workflows

**Step 1: Delete DynamoDB state lock**
```bash
# Navigate to: DynamoDB > Tables > STATE_LOCK_TABLE
# Delete the lock item
# OR: terraform force-unlock LOCK_ID
```

**Step 2: Fix checksum mismatch**
```bash
# Get current S3 state checksum
aws s3 cp s3://BUCKET/STATE_KEY - | md5sum

# Update DynamoDB digest to match S3 checksum
# DynamoDB > Tables > STATE_LOCK_TABLE > Find item > Update Digest attribute
```

**Step 3: Cancel secret deletions**
```
AWS Console > Secrets Manager > Each secret > Cancel deletion
```

**Step 4: Verify state**
```bash
terraform plan  # Should work without errors
```

**Step 5: Implement approval gate (CRITICAL)**

File: `.github/workflows/dev-aws-secrets.yml`
```yaml
review-window:
  needs: plan
  steps:
    - name: REVIEW BEFORE APPLY
      run: |
        echo "=========================================="
        echo "  CHECK PLAN OUTPUT FOR:"
        echo "  - Resource DELETIONS (red minus signs)"
        echo "  - Unexpected changes"
        echo "  - Name mismatches"
        echo ""
        echo "  CANCEL WORKFLOW if anything looks wrong"
        echo "  Waiting 3 minutes..."
        echo "=========================================="
        sleep 180
```

**Step 6: Enable S3 state versioning**
```bash
# Allows rollback to previous state versions
aws s3api put-bucket-versioning \
  --bucket hybrid-cloud-infrastructure-tf-state-dev \
  --versioning-configuration Status=Enabled
```

## 6. Solution Risk
- Risk level: MEDIUM
- Potential impact: Manual DynamoDB edit could corrupt lock if done incorrectly. Always backup before modifying.

## 7. Impact After Fix
- Observed: All secrets restored, no data loss
- 3-minute review window prevents future accidents
- S3 versioning allows state rollback
- Recovery time: ~30 minutes

**Affected secrets (all restored):**
- dev/proxmox/terraform-token (CRITICAL)
- dev/proxmox/ssh-admin-password (CRITICAL)
- dev/proxmox/vm-root-password (HIGH)
- dev/vm/gandalf-password (MEDIUM)

## 8. Notes

**State file recovery from S3 versions:**
```bash
# List state file versions
aws s3api list-object-versions \
  --bucket BUCKET_NAME \
  --prefix STATE_KEY

# Download previous version
aws s3api get-object \
  --bucket BUCKET_NAME \
  --key STATE_KEY \
  --version-id VERSION_ID \
  state-backup.tfstate
```

**Lessons learned:**
1. Workflow cancellation doesn't guarantee rollback
2. Always verify state file integrity after cancellation
3. 3-minute delay provides manual review window
4. S3 versioning is essential for state recovery
5. Check AWS Console for scheduled deletions

**Related:** TS-GH-002 (workflow lock flag pattern) implements additional protection layer.

## 9. Workaround (if any)
> If approval gate not implemented: Manually run `terraform plan` locally first, review output carefully, then trigger workflow only if plan looks safe.
