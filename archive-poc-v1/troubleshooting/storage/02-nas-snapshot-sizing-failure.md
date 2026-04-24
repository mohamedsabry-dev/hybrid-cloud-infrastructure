━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TROUBLESHOOTING CASE #02: NAS VM SNAPSHOT SIZING FAILURE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Category: Storage / Resource Allocation
Severity: Critical
Incident: Yes
Environment: ESXi Master → NAS VM
Source: Draft for Resource Allocation (Lines 347-371)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PROBLEM DESCRIPTION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Issue: NAS VM Snapshot Task Failed and VM Entered Maintenance Mode

Configuration:
  ├── NAS VM: 980GB thick provisioned disk
  ├── Datastore: Only 450GB available space
  └── Operation: vCenter requested snapshot

Symptom:
  ├── Snapshot task stuck (didn't progress)
  ├── Next boot: NAS VM entered Linux maintenance mode
  └── Error: Storage not found

vCenter Event Log:
  └── "Failed snapshot - datastore space insufficient: 450 < 980"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ROOT CAUSE ANALYSIS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

VMware Snapshot Behavior:
  ├── Phase 1: vCenter requests datastore space = full disk size
  ├── For thick disk: Requires space equal to entire disk capacity
  ├── Thick provisioned VM (980GB) needs 980GB free space for snapshot
  └── Available space (450GB) < Required space (980GB) → FAILURE

Why This Happens:
  ├── Thick provisioned disks allocate full space upfront
  ├── Snapshot creates delta file to capture changes
  ├── Worst case: Delta file could grow to full disk size
  └── vCenter pre-allocates space to prevent snapshot corruption

Impact:
  ├── Snapshot operation hung
  ├── VM state inconsistent
  ├── On reboot: Filesystem mount failed
  └── NAS entered emergency maintenance mode

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RECOVERY PROCEDURE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Immediate Recovery Steps:

Step 1: Shutdown NAS VM
  └── Stop the VM to prevent further corruption

Step 2: Extend Datastore Capacity
  ├── Add vDisk with more space (temporary fix)
  └── Extend datastore to provide required space

Step 3: Resume Snapshot Task
  └── Snapshot task resumed automatically after space available

Step 4: Start NAS VM
  └── Verified normal operation

Step 5: Clean Up Corrupted Snapshot
  └── Delete potentially corrupted snapshot from vCenter

Step 6: Take Fresh Snapshot
  └── Verified successful completion with adequate space

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PERMANENT SOLUTION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Storage Refactoring - Create Dedicated Datastore:

New Architecture:
  ├── Create DS_NVME_2 datastore (2TB capacity)
  ├── Move NAS VM to DS_NVME_2
  ├── NAS VM disk: 980GB thick provisioned
  └── Available space: >1TB (sufficient for snapshots)

Sizing Rules for Thick Provisioned VMs:
  ├── Required datastore capacity ≥ 2x VM disk size
  ├── Formula: Datastore Size = (VM Disk Size × 2) + 20% buffer
  ├── Example: 980GB VM → Minimum 2.35TB datastore
  └── Safe Zone: Total usage < 85% of datastore capacity

Implementation:
  ├── NAS VM (980GB) → DS_NVME_2 (2TB)
  ├── Maximum snapshot size: 980GB
  ├── Total usage: 1.96TB < 2TB (Safe zone confirmed)
  └── Result: Snapshots work reliably

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
LESSONS LEARNED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Critical Insights:
  Yes Thick provisioned VMs need datastore capacity ≥ 2x disk size for snapshots
  Yes Always plan datastore sizing based on THICK disk requirements
  Yes vCenter snapshot space calculation includes full disk size
  Yes Insufficient space causes snapshot failure AND VM corruption risk

Storage Planning Best Practices:
  Yes Calculate snapshot overhead during design phase
  Yes Use dedicated datastores for thick provisioned critical VMs
  Yes Monitor datastore free space before snapshot operations
  Yes Consider thin provisioning for VMs requiring frequent snapshots

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PREVENTION MEASURES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Design Phase:
  Yes Calculate worst-case snapshot requirements
  Yes Use formula: Datastore = (VM Size × 2) + 20%
  Yes Allocate dedicated datastores for large thick VMs
  Yes Document datastore sizing decisions

Monitoring:
  Yes Set vCenter alarms for datastore capacity < 50%
  Yes Monitor snapshot chain length
  Yes Track snapshot age (delete old snapshots)
  Yes Regular datastore capacity reviews

Operational:
  Yes Verify free space before manual snapshots
  Yes Configure automated snapshot cleanup
  Yes Test snapshot operations in staging first
  Yes Always maintain 2x disk size free space for thick VMs

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RELATED ISSUES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  • Issue #01: VMDK Snapshot Corruption (Storage organization)
  • Issue #05: Thick-to-Thin Conversion (Alternative solution)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
