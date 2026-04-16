# TS-TF-002 | 2026-02-14 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Terraform / AWS
Sub-techs: Terraform state, AWS Secrets Manager, S3 backend, DynamoDB lock,
           GitHub Actions, approval gate, S3 versioning
Environment: AWS Dev Account eu-west-2
Re-opened: No

_____________________________________________________________________

[Issue Description]
Terraform workflow accidentally scheduled deletion of all AWS Secrets Manager
secrets. State file corrupted from normal 14KB down to 299 bytes.

  S3 checksum:       47f5e65e55b95a3605ffc0cd496960d7
  DynamoDB checksum: ae0fd0e5a2f149fb1f7ffc54d85a9507
  (mismatch — state inconsistent)

Timeline:
  Feb 12 ~8:00 PM  Made small name change to Terraform secrets config.
                   Workflow triggered — noticed destroy in plan — canceled workflow.
  Feb 14 10:00 AM  Discovered all secrets missing from AWS Console.
                   State file only 299 bytes. Secrets scheduled for deletion.

Affected secrets:
  dev/proxmox/terraform-token        CRITICAL
  dev/proxmox/ssh-admin-password     CRITICAL
  dev/proxmox/vm-root-password       HIGH
  dev/vm/gandalf-password            MEDIUM

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Checked what caused the deletion and why canceling the workflow did not prevent it.

Terraform name change triggered resource replacement:
  Old resource: scheduled for DELETE
  New resource: scheduled for CREATE
  Workflow canceled mid-execution.
  State partially updated — secrets already entered deletion queue before cancel.

Workflow cancellation in GitHub Actions does NOT guarantee rollback of AWS API
calls that already completed. The delete call reached AWS Secrets Manager before
the cancel was processed.

Checked state file size:
  Normal: 14.0 KB (14,336 bytes)
  Current: 299 bytes
  Reduction: 98% — state effectively empty.
  Corruption mechanism: likely mid-write when workflow was canceled.

Checked AWS Secrets Manager:
  All secrets present in console as "scheduled for deletion".
  AWS Secrets Manager deletion window: 7-30 days.
  All secrets recoverable before window expires.


# Suspected Root Cause
No approval gate between terraform plan and apply. Workflow triggered automatically
on push. Cancellation occurred after the delete API calls had already reached AWS —
state partially updated, secrets in deletion queue, state file corrupted.


# More Checks Notes:
DynamoDB lock item still present from the canceled workflow — blocking all
subsequent Terraform operations.


# Suspected Solution
  1. Clear DynamoDB lock
  2. Fix checksum mismatch between S3 and DynamoDB
  3. Cancel secret deletions in AWS Console
  4. Verify state
  5. Add approval gate to workflow
  6. Enable S3 state versioning for future recovery


# Test
Ran terraform plan after fix steps — completed without errors.
Verified all secrets accessible in AWS Console.

Result: PASS — all secrets restored, state consistent, no data loss.
Recovery time: ~30 minutes.

_____________________________________________________________________

[Final Root Cause]
No approval gate between terraform plan and apply. Automatic workflow trigger
on push gave limited time to review plan output. Workflow cancellation occurred
after delete API calls had already been sent to AWS Secrets Manager — canceling
the workflow does not roll back completed AWS API calls. State file partially
written on cancellation, corrupted to 299 bytes with checksum mismatch between
S3 and DynamoDB.

_____________________________________________________________________

[Final Solution]

Step 1 — Clear DynamoDB state lock:
  AWS Console → DynamoDB → Tables → STATE_LOCK_TABLE → delete the lock item
  Or: terraform force-unlock LOCK_ID

Step 2 — Fix checksum mismatch:
  # Get current S3 state checksum
  aws s3 cp s3://BUCKET/STATE_KEY - | md5sum

  # Update DynamoDB digest to match S3 checksum
  DynamoDB → Tables → STATE_LOCK_TABLE → find item → update Digest attribute

  Note: Always backup before modifying DynamoDB lock table manually.

Step 3 — Cancel secret deletions:
  AWS Console → Secrets Manager → each secret → Cancel deletion

Step 4 — Verify state:
  terraform plan  # should complete without errors

Step 5 — Add approval gate to workflow (.github/workflows/dev-aws-secrets.yml):
  review-window:
    needs: plan
    steps:
      - name: REVIEW BEFORE APPLY
        run: |
          echo "CHECK PLAN OUTPUT FOR:"
          echo "  - Resource DELETIONS (red minus signs)"
          echo "  - Unexpected changes"
          echo "  - Name mismatches"
          echo "CANCEL WORKFLOW if anything looks wrong. Waiting 3 minutes..."
          sleep 180

Step 6 — Enable S3 state versioning:
  aws s3api put-bucket-versioning \
    --bucket hybrid-cloud-infrastructure-tf-state-dev \
    --versioning-configuration Status=Enabled

Verified: Yes

_____________________________________________________________________

[Risk Level] MEDIUM
Note: Manual DynamoDB edit could corrupt lock if done incorrectly.
Always backup state and lock item before modifying.

_____________________________________________________________________

[References]
- TS-GH-002 — workflow lock flag pattern (additional protection layer)

_____________________________________________________________________

[Draft Notes]

Key lessons:
  1. Workflow cancellation does NOT guarantee rollback of AWS API calls already sent
  2. Always verify state file integrity after any workflow cancellation
  3. Approval gate (3-minute delay) provides a manual review window before apply
  4. S3 versioning is essential for state recovery — enable from day one
  5. Check AWS Console for scheduled deletions after any state issue
  6. A "small name change" in Terraform can trigger full resource replacement

State file recovery from S3 versions (if versioning was enabled):
  aws s3api list-object-versions --bucket BUCKET_NAME --prefix STATE_KEY
  aws s3api get-object \
    --bucket BUCKET_NAME \
    --key STATE_KEY \
    --version-id VERSION_ID \
    state-backup.tfstate

Workaround if approval gate not implemented:
  Run terraform plan locally first.
  Review output carefully before triggering workflow.
  Never trigger apply without confirming plan shows no unexpected deletions.