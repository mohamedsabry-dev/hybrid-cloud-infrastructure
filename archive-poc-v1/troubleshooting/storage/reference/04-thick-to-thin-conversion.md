━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TROUBLESHOOTING CASE #06: THICK-TO-THIN DISK CONVERSION (RISKY OPERATION)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Category: Resource Allocation / Storage
Severity: CRITICAL (RISKY OPERATION)
Environment: ESXi Nested 2 / VMware vSphere
Source: Draft for Resource Allocation (Lines 397-570)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  RISK ASSESSMENT - READ CAREFULLY 
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

"This operation is EXTREMELY RISKY and varies based on whether disk is single
file or multi-file. This was done for learning purposes. DO NOT attempt this
headache from the beginning if possible. Such operations should be performed
by product support engineers with full RFC (Request For Change) planned and
reviewed. In real life, we don't create nested labs anyway. The thick/thin
issue may be encountered in other contexts."

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PROBLEM DESCRIPTION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Issue: ESXi Nested 2 Snapshot Size Abnormally Large

Discovery:
  ├── ESXi Nested 1 snapshot: 3GB (normal)
  ├── ESXi Nested 2 snapshot: 150GB (abnormal!)
  └── Root Cause: ESXi Nested 2 created with thick provisioning

Random Choice During Setup:
  └── One nested ESXi accidentally configured as thick instead of thin

Impact:
  ├── Snapshot operations consume excessive storage
  ├── Datastore space exhaustion risk
  ├── Backup operations slow
  └── Inconsistent provisioning across environment

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DECISION: CONVERT ESXi NESTED 2 FROM THICK TO THIN
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Why Convert:
  ├── Reduce snapshot size from 150GB to ~3GB
  ├── Free up datastore space
  ├── Standardize provisioning across environment
  └── Learning opportunity for disk operations

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CONVERSION PROCEDURE (SSH + vmkfstools Method)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PHASE 1: Backup & Preparation

Step 1: Create Backup
  └── Backup ESXi Nested 2 VM using Veeam or export as OVF

Step 2: Create Template
  └── Convert ESXi Nested 2 to template and store in safe location

Step 3: Snapshot ESXi Nested 2
    CANNOT snapshot ESXi Nested 2 directly (thick disk too large)
  └── This is why we are doing this refactor

Step 4: Snapshot ESXi Master
  └── Protection for host-level changes

Step 5: Evacuate Workload
  ├── Migrate all VMs from ESXi Nested 2 to ESXi Nested 1
  └── Ensures no production impact during conversion

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PHASE 2: Consolidate Snapshots

Step 6: Delete Old Snapshots of ESXi Nested 2
  Location: ESXi Master → Snapshot Manager → ESXi Nested 2

  Why Delete Old Snapshots First?
    ├── When snapshot exists: Pointer → *-000001.vmdk (locks parent)
    ├── Need single consolidated file for vmkfstools conversion
    ├── Deleting snapshots: ESXi consolidates history into parent .vmdk file
    └── Result: Single file to copy = full history preserved

  Procedure:
    ├── Better to copy snapshots to safe place first
    └── Then delete from Snapshot Manager

Step 7: Shutdown ESXi Nested 2
  └── Prepare for disk conversion

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PHASE 3: SSH Conversion Using vmkfstools

Step 8: Enable SSH on ESXi Master
  └── SSH into ESXi Master

Step 9: Navigate to VM Storage
  Command:
    cd /vmfs/volumes/<datastore>/Nested-ESXi-2/
    ls -lh *.vmdk

Step 10: Verify Clean State
  Should see ONLY:
    ├── Nested-ESXi-2.vmdk (descriptor file)
    └── Nested-ESXi-2-flat.vmdk (data file)

  Should NOT see:
    └── *-000001.vmdk, *-000002.vmdk, etc. (snapshot deltas)

Step 11: Check VMDK Type
  Command:
    cat Nested-ESXi-2.vmdk | grep -E "ddb.adapterType|createType"

  Expected:
    createType="monolithicFlat" (thick)

Step 12: Convert to Thin Provisioning
  Command:
    vmkfstools -i Nested-ESXi-2.vmdk -d thin Nested-ESXi-2-THIN.vmdk

  This creates:
    ├── Nested-ESXi-2-THIN.vmdk (descriptor file)
    └── Nested-ESXi-2-THIN-flat.vmdk (actual data, thin provisioned)

Step 13: Verify Conversion
  Check disk type:
    Command:
      cat Nested-ESXi-2-THIN.vmdk | grep createType

    Expected:
      createType="vmfs" (thin)

  Compare file sizes:
    Command:
      ls -lh Nested-ESXi-2*.vmdk

    Result:
      • Original thick: ~150GB allocated
      • New thin: ~20GB allocated (only used space)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PHASE 4: Update VM Configuration

Step 14: Remove Old Thick Disk from VM
  Via ESXi Master Web UI:
    ├── Select Nested ESXi 2 VM
    ├── Actions → Edit Settings
    ├── Find "Hard disk 1" (the OS disk)
    ├── Click (X) to remove
    ├── Select "Remove from virtual machine" (NOT "Delete from disk")
    └── Click Save

  Why "Remove from virtual machine"?
    Yes Keeps original thick VMDK as backup until operation confirmed
    Yes Allows rollback if something goes wrong
    Yes Can delete manually later after full verification

Step 15: Add New Thin Disk
  Via ESXi Master Web UI:
    ├── Select Nested ESXi 2 VM
    ├── Actions → Edit Settings
    ├── Click "Add hard disk" → "Existing hard disk"
    ├── Browse to: [datastore] Nested-ESXi-2/Nested-ESXi-2-THIN.vmdk
    ├── Verify Controller location: SCSI 0:0
    └── Click Save

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PHASE 5: Testing & Verification

Step 16: Power On and Verify Boot
  Via ESXi Master Web UI:
    ├── Power on Nested ESXi 2
    ├── Open console
    ├── Verify ESXi boots normally
    ├── Log into Nested ESXi 2 web interface
    ├── Check all datastores visible
    └── Verify VMs present (if any)

Step 17: Verify from Inside Nested ESXi 2
  SSH to Nested ESXi 2:
    df -h
    esxcli storage filesystem list

Step 18: Verify File State on ESXi Master
  SSH to ESXi Master:
    cd /vmfs/volumes/<datastore>/Nested-ESXi-2/
    ls -lh

  Should see:
    ├── Nested-ESXi-2-THIN.vmdk (in use)
    ├── Nested-ESXi-2-THIN-flat.vmdk (in use)
    ├── Nested-ESXi-2.vmdk (old backup - can delete later)
    └── Nested-ESXi-2-flat.vmdk (old backup - can delete later)

Step 19: Soak Test (Wait 1 Day)
  └── Verify all workload and operations normal on ESXi Nested 2

Step 20: Clean Up Old Files
  SSH to ESXi Master:
    cd /vmfs/volumes/<datastore>/Nested-ESXi-2/
    rm Nested-ESXi-2.vmdk
    rm Nested-ESXi-2-flat.vmdk

Step 21: Take Fresh Snapshot
  └── With thin provisioning, snapshot should be < 5GB

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  PRODUCTION WARNING 
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

"This operation is EXTREMELY risky and varies based on disk structure (single
file vs multi-file). Done for learning purposes only. Such operations should
be performed by product support engineers with full RFC (Request For Change)
planned and reviewed. In production, we don't create nested labs - but the
thick/thin issue may be encountered in other scenarios."

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
LESSONS LEARNED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Key Insights:
  Yes Always standardize provisioning type during initial deployment
  Yes Thick-to-thin conversion is high-risk operation
  Yes Requires multiple backups and careful planning
  Yes Snapshot consolidation is critical before conversion
  Yes Keep old files until fully verified

Best Practices:
  Yes Document provisioning decisions at design time
  Yes Use consistent provisioning across similar VMs
  Yes Test disk operations in staging first
  Yes Maintain rollback capability throughout process
  Yes Verify boot and functionality before cleanup

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PREVENTION MEASURES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Design Phase:
  Yes Choose provisioning type BEFORE creating VMs
  Yes Document standard: All thin OR all thick (no mixing)
  Yes Create VM deployment checklist
  Yes Review provisioning settings during peer review

Deployment:
  Yes Use templates with correct provisioning
  Yes Double-check disk type during VM creation
  Yes Verify provisioning immediately after creation
  Yes Document actual provisioning in CMDB

Monitoring:
  Yes Regular audit of VM provisioning types
  Yes Alert on mixed provisioning in same environment
  Yes Track snapshot sizes for anomalies
  Yes Monitor datastore capacity trends

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RELATED ISSUES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  • Issue #02: NAS VM Snapshot Sizing (Thick provisioning challenges)
  • Issue #01: Storage organization and standardization

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
