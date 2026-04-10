━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TROUBLESHOOTING CASE #01: VMDK SNAPSHOT CORRUPTION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Category: Storage
Severity: High
Environment: VMware Workstation → ESXi Master
Source: Draft for Storage (Lines 75-80)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PROBLEM DESCRIPTION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Issue: VMDK Snapshot Corruption

Trigger:
  └── Deleted snapshots from VMware Workstation snapshot manager

Symptom:
  └── 2 vDisks with versioned VMDK files (00000x.vmdk) missing parent files

Root Cause:
  ├── vDisks located in different partitions than ESXi Master folder
  └── vDisks separated from where main OS and all snapshots/versions live

Impact:
  └── Corruption and data loss risk

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ROOT CAUSE ANALYSIS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Design Flaw:
  ├── Old Design: 5 vDisks for VMware Workstation (ESXi Master)
  ├── Problem: vDisks distributed across 2 physical disks in laptop
  └── Architecture: Spaghetti storage with no clear organizational strategy

Technical Issue:
  ├── VMware Workstation snapshots create delta files (.vmdk-000001, etc.)
  ├── Delta files must be in same location as base VMDK
  ├── When vDisks are in different partitions, snapshot chain breaks
  └── Deleting snapshots without consolidation causes orphaned deltas

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SOLUTION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Storage Refactoring (Complete Rebuild):

Step 1: Create New Consolidated vDisks
  ├── Create 2 new vDisks: 2000GB each
  ├── Format: Thin provisioned, single file
  ├── Location: Same ESXi Master folder (CRITICAL!)
  └── Naming: nvme_ds_1 and nvme_ds_2 (clear descriptive names)

Step 2: Migrate All VMs to New Datastores
  ├── Use vCenter migration wizard
  ├── Strategy:
  │     • DS_NVME_02: NAS VM only
  │     • DS_NVME_01: Everything else
  └── Move ISO folder and Content Library manually

Step 3: Validate Environment
  ├── Verify old datastores are empty
  ├── Run environment and test all services
  └── Shutdown environment and ESXi Master

Step 4: Remove Old Infrastructure
  ├── Unmount old datastores in vCenter
  ├── Remove from inventory
  ├── Shutdown ESXi Master
  └── In VMware Workstation: Set old 4 vDisks to "not connected"

Step 5: Final Verification
  ├── Run environment again
  ├── Verify everything works correctly
  └── After confirmation: Safely delete old vDisks from physical disk

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
LESSONS LEARNED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

"Bad design is good to learn from. Be cautious about what you are building.
Make it stable, clean, easy to manage, and easy to troubleshoot later."

Principles:
  ✓ Keep all related files in the same location
  ✓ Use clear, descriptive naming conventions
  ✓ Standardize provisioning types (all thin or all thick)
  ✓ Always take snapshots before risky operations
  ✓ Test thoroughly before deleting old infrastructure
  ✓ Document your architecture for future reference

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PREVENTION MEASURES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Design Phase:
  ✓ Plan storage architecture before creating vDisks
  ✓ All vDisks for a VM should be in same directory
  ✓ Use consistent provisioning (all thin OR all thick)
  ✓ Avoid mixing storage locations

Naming Convention:
  ✓ Use descriptive names that indicate purpose
  ✓ Bad: "datastore1", "datastore2"
  ✓ Good: "DS_NVME_01", "NAS_DS_1"

Snapshot Management:
  ✓ Always consolidate snapshots before deletion
  ✓ Never delete snapshot files manually from filesystem
  ✓ Use vCenter/VMware Workstation snapshot manager only

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RELATED ISSUES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  • Issue #02: NAS VM Snapshot Sizing (Thick provisioning)
  • Issue #05: Thick-to-Thin Disk Conversion (Snapshot size problems)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
