================================================================================
                    INCIDENT REPORT: AWS Secrets Deletion
================================================================================

Incident ID: INC-2026-02-14-001
Date: February 14, 2026
Time: 10:00 AM EGT
Severity: HIGH
Status: RESOLVED
Environment: AWS Dev Account (018571635409)

================================================================================
                              EXECUTIVE SUMMARY
================================================================================

Terraform workflow accidentally scheduled deletion of all AWS Secrets Manager
secrets in dev environment due to code change. State file became corrupted
(299 bytes vs normal 14KB). All secrets restored successfully with no data loss.
Root cause: Lack of approval gates between terraform plan and apply.

Impact Duration: ~30 minutes
Data Loss: None (secrets restored from deletion queue)
Service Disruption: None (caught before deletion completed)

================================================================================
                              INCIDENT TIMELINE
================================================================================

February 12, 2026 (~8:00 PM):
  - Made "small name change" to Terraform secrets configuration
  - Workflow triggered automatically
  - Noticed destroy operations in plan output at last second
  - Canceled workflow before apply completed
  - Believed incident was prevented

February 14, 2026 (10:00 AM):
  - Routine check of AWS Secrets Manager GUI
  - Discovery: All secrets missing from GUI
  - Investigation: S3 state file only 299 bytes (normally 14KB)
  - Realization: Secrets were scheduled for deletion despite canceling workflow

Recovery Actions (10:00 AM - 10:30 AM):
  1. Deleted DynamoDB state lock
  2. Attempted terraform plan
  3. Error: State checksum mismatch (S3 vs DynamoDB)
     - S3 checksum:      47f5e65e55b95a3605ffc0cd496960d7
     - DynamoDB checksum: ae0fd0e5a2f149fb1f7ffc54d85a9507
  4. Manually updated DynamoDB digest to match S3 checksum
  5. Found secrets in AWS Console scheduled for deletion (6-7 total)
  6. Canceled scheduled deletion for all secrets
  7. Restored all secrets from deletion queue
  8. Removed DynamoDB lock again
  9. Ran terraform plan (read-only)
  10. Terraform detected extra secrets not in code
  11. Compared AWS secrets vs Terraform code (4 secrets expected)
  12. Deleted 2-3 untracked secrets (old/manual entries)
  13. Verified state stable and matching code
  14. System restored to normal operation

================================================================================
                              ROOT CAUSE ANALYSIS
================================================================================

Primary Cause:
  Terraform name change triggered resource replacement:
  - Old resource: DELETE
  - New resource: CREATE
  - Workflow canceled mid-execution
  - State partially updated
  - Secrets entered deletion queue despite cancel

Contributing Factors:
  1. No approval gate between plan and apply
  2. Automatic workflow trigger on push
  3. Limited time to review plan output before apply executes
  4. Working solo - no peer review of changes
  5. State file corruption (299 bytes) - cause unclear
  6. Checksum mismatch between S3 state and DynamoDB lock

Why Cancel Failed to Prevent Deletion:
  - Workflow cancellation may have occurred after state update
  - OR: Workflow re-ran automatically after cancellation
  - OR: State update committed before apply was fully canceled
  - Exact mechanism unclear - requires further investigation

================================================================================
                           AFFECTED RESOURCES
================================================================================

Secrets Scheduled for Deletion (6-7 total):
  - dev/proxmox/terraform-token (CRITICAL - Proxmox API access)
  - dev/proxmox/ssh-admin-password (CRITICAL - Proxmox management)
  - dev/proxmox/vm-root-password (HIGH - VM access)
  - dev/vm/gandalf-password (MEDIUM - Break-glass user)
  - [2-3 additional secrets - old/untracked]

Expected Secrets (per Terraform code):
  - 4 secrets total
  - All restored successfully

State Files:
  - S3 tfstate: Corrupted to 299 bytes (normally 14KB)
  - DynamoDB lock: Checksum mismatch with S3 state
  - Both manually repaired

================================================================================
                              IMPACT ASSESSMENT
================================================================================

Actual Impact:
  - No data loss (secrets restored from deletion queue)
  - No service disruption (caught before 7-30 day deletion window expired)
  - ~30 minutes recovery time
  - Manual intervention required

Potential Impact (if not caught):
  - Complete loss of automation credentials after deletion window
  - Loss of Proxmox API access
  - Loss of VM root passwords
  - Days of manual credential recreation
  - Broken CI/CD pipelines
  - Manual reconfiguration of all services

Risk Level: HIGH
  - Critical credentials at risk
  - No automated backup of secret values
  - Solo operation - no team to assist recovery
  - Working knowledge of state recovery required

================================================================================
                              LESSONS LEARNED
================================================================================

What Went Well:
  ✓ Noticed state file size anomaly (299 bytes)
  ✓ Checked AWS Console for scheduled deletions
  ✓ Understood Terraform state/lock relationship
  ✓ Successfully performed manual state recovery
  ✓ Documented incident immediately

What Went Wrong:
  ✗ No approval gate between plan and apply
  ✗ Assumed workflow cancellation prevented all changes
  ✗ Didn't verify state file integrity after cancellation
  ✗ No alerting for secret deletions
  ✗ State file corruption mechanism unclear

Knowledge Gaps Identified:
  - Exact workflow cancellation behavior unclear
  - When does state update commit vs rollback?
  - What causes state file corruption to 299 bytes?
  - How to prevent checksum mismatches?

================================================================================
                           PREVENTION MEASURES
================================================================================

Implemented Immediately:

1. Approval Gate via Delay (CRITICAL)
   - Added 3-minute review window to all terraform workflows
   - Manual cancellation window before apply executes
   - Clear instructions in workflow output
   
   Code:
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

2. S3 State Versioning (HIGH)
   - Enabled versioning on terraform state bucket
   - Allows rollback to previous state versions
   - Recovery option if state corrupts again

3. Incident Documentation (MEDIUM)
   - Created this incident report
   - Documented recovery procedures
   - Knowledge base for future incidents

Planned for Future:

4. State File Monitoring (MEDIUM)
   - Alert on state file size anomalies
   - Alert on checksum mismatches
   - Automated state backup before apply

5. Secret Deletion Monitoring (MEDIUM)
   - EventBridge rule for DeleteSecret API calls
   - SNS notification on secret deletions
   - Early warning system

6. Dry-Run Environment (LOW)
   - Separate "test" environment for risky changes
   - Validate destructive changes before dev/prod
   - Lower priority - budget constraints

================================================================================
                           RECOVERY PROCEDURES
================================================================================

State Checksum Mismatch Recovery:

1. Identify current state checksum:
```bash
   aws s3api head-object \
     --bucket BUCKET_NAME \
     --key STATE_KEY \
     --checksum-mode ENABLED
```

2. Get checksum from error message or calculate:
```bash
   aws s3 cp s3://BUCKET/STATE_KEY - | md5sum
```

3. Update DynamoDB digest:
   - Navigate to: DynamoDB > Tables > STATE_LOCK_TABLE
   - Find item with LockID matching state key
   - Update Digest attribute to match calculated checksum
   - Save item

4. Remove state lock:
   - Delete the lock item from DynamoDB
   - OR: `terraform force-unlock LOCK_ID`

5. Verify state recovery:
```bash
   terraform plan  # Should work without errors
```

Secret Deletion Recovery:

1. Check AWS Secrets Manager Console for scheduled deletions
2. For each secret scheduled for deletion:
   - Click secret name
   - Click "Cancel deletion"
   - Verify secret is active again
3. Run terraform plan to verify state matches reality
4. Clean up any untracked secrets manually

State File Corruption Recovery:

1. List S3 state file versions:
```bash
   aws s3api list-object-versions \
     --bucket BUCKET_NAME \
     --prefix STATE_KEY
```

2. Identify last known-good version (by timestamp and size)
3. Download previous version:
```bash
   aws s3api get-object \
     --bucket BUCKET_NAME \
     --key STATE_KEY \
     --version-id VERSION_ID \
     state-backup.tfstate
```

4. Compare with current state and restore if needed
5. Update DynamoDB checksum to match restored state

================================================================================
                              NEXT STEPS
================================================================================

Immediate (Today):
  [✓] Add 3-minute delay to all workflows
  [✓] Enable S3 state versioning
  [✓] Document incident

This Week:
  [ ] Review all terraform workflows for safety
  [ ] Add state file size monitoring
  [ ] Test approval gate with intentional destroy
  [ ] Validate cancellation behavior

This Month:
  [ ] Implement secret deletion monitoring
  [ ] Create automated state backups
  [ ] Document all terraform workflows
  [ ] Add pre-apply validation checks

================================================================================
                           TECHNICAL DETAILS
================================================================================

Environment Details:
  - AWS Account: 018571635409 (dev)
  - Region: eu-west-2
  - Terraform Version: 1.14.3
  - State Bucket: hybrid-cloud-infrastructure-tf-state-dev
  - Lock Table: hybrid-cloud-infrastructure-tf-state-lock-dev
  - Workflow: .github/workflows/dev-aws-secrets.yml (assumed)

State File Analysis:
  - Normal state size: 14.0 KB (14,336 bytes)
  - Corrupted state size: 299 bytes
  - Size reduction: 98% (13,937 bytes lost)
  - Corruption cause: Unknown - requires investigation
  - Recovery: Secrets restored, state rebuilt

Checksum Details:
  - Algorithm: MD5
  - S3 checksum:      47f5e65e55b95a3605ffc0cd496960d7
  - DynamoDB checksum: ae0fd0e5a2f149fb1f7ffc54d85a9507
  - Resolution: Manual update to match S3

================================================================================
                              REFERENCES
================================================================================

Related Documentation:
  - docs/01-aws-iam-bootstrap.txt (AWS setup)
  - docs/02-cicd-workflows.txt (Workflow patterns)
  - .github/workflows/ (All workflow files)

Terraform State Locking:
  - https://developer.hashicorp.com/terraform/language/state/locking
  - S3 + DynamoDB backend configuration

AWS Secrets Manager:
  - Deletion window: 7-30 days (configurable)
  - Recovery: Possible before deletion window expires
  - https://docs.aws.amazon.com/secretsmanager/

================================================================================
                           INCIDENT REPORT METADATA
================================================================================

Report Created: February 14, 2026, 10:45 AM EGT
Created By: Infrastructure Engineer (Solo)
Report Status: FINAL
Distribution: Internal documentation only
Next Review: March 14, 2026 (30 days)

Sign-off:
  Incident Commander: Self (solo operation)
  Technical Lead: Self (solo operation)
  Post-Incident Review: Scheduled for February 21, 2026

================================================================================