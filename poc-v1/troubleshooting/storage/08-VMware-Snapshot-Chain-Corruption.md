================================================================================
CASE: VMware Snapshot Chain Corruption - Parent VMDK Link Broken
================================================================================
Category: Storage - VMware Workstation Snapshots
Severity: Critical (Data Loss Risk)
Date: Snapshot Deletion Operation
Environment: VMware Workstation, ESXi Master with Multiple Datastores
Error: "Parent virtual disk has been modified"

================================================================================
SYMPTOM
================================================================================
- VMs won't boot after snapshot deletion
- Datastores show as "inaccessible" in ESXi
- Error message: "Parent virtual disk has been modified"
- Lost access to nested ESXi hosts and VMs
- VMware Workstation shows snapshot tree but disks are broken
- ESXi management interface accessible but datastores offline

Visual Symptoms:
- ESXi Web UI: Datastore Browser shows "Unknown" status
- VM Console: Boot fails with disk error
- VMware Workstation: Snapshot Manager shows chain but operations fail

================================================================================
ROOT CAUSE
================================================================================
VMware snapshot deletion fails when parent VMDK and child delta disks are
stored in different directories/drives. The snapshot chain breaks because
child disks cannot find their parent after consolidation.

Technical Background: VMware Snapshot Chain
--------------------------------------------
Snapshots create a parent-child chain of VMDK files:

Normal Chain (Working):
/VMs/ESXi-Master/
  ├── ESXi-Disk.vmdk (parent - base disk)
  ├── ESXi-Disk-flat.vmdk (parent data file)
  ├── ESXi-Disk-00001.vmdk (snapshot 1 - child of base)
  ├── ESXi-Disk-00001-delta.vmdk (snapshot 1 data)
  ├── ESXi-Disk-00002.vmdk (snapshot 2 - child of 00001)
  └── ESXi-Disk-00002-delta.vmdk (snapshot 2 data)

Each child VMDK descriptor contains reference to parent:
  parentFileNameHint="ESXi-Disk-00001.vmdk"

Broken Chain (After Moving Files):
C:/VMs/ESXi-Master/
  ├── ESXi-Disk-00001.vmdk (child - looking for parent)
  └── ESXi-Disk-00001-delta.vmdk

D:/Overflow/
  ├── ESXi-Disk.vmdk (parent - wrong location!)
  └── ESXi-Disk-flat.vmdk

Child VMDK still references:
  parentFileNameHint="D:/Overflow/ESXi-Disk.vmdk"

When trying to consolidate/delete snapshots:
1. VMware Snapshot Manager attempts to merge delta disks
2. Looks for parent at original path
3. If parent moved or path changed, merge fails
4. Chain corruption occurs
5. Disk becomes unbootable

================================================================================
HOW THIS HAPPENED: AD-HOC STORAGE GROWTH ANTI-PATTERN
================================================================================

Bad Practice: Storing VMDKs Across Multiple Drives
---------------------------------------------------
Initial setup:
1. Created ESXi Master with 150GB OS disk on C:\VMs\
2. Ran out of space, added 1TB disk, stored on D:\Overflow\
3. Added another 1TB disk later, stored on E:\ExtraDrive\
4. Created snapshots in VMware Workstation for testing
5. Accumulated 5+ snapshots over time
6. Hit snapshot chain depth limit (VMware warning)
7. Decided to delete old snapshots to reclaim space
8. Used VMware Snapshot Manager to delete snapshots
9. DISASTER: Parent-child VMDK links broke

Storage Layout That Failed:
----------------------------
C:\VMs\ESXi-Master\
  ├── ESXi-Master.vmx
  ├── ESXi-Master-OS.vmdk (150GB, thick)
  ├── ESXi-Master-OS-flat.vmdk
  └── vmware.log

D:\Overflow\
  ├── ESXi-Master-Disk2.vmdk (1TB, thin - parent)
  ├── ESXi-Master-Disk2-flat.vmdk
  └── ESXi-Master-Disk2-00001.vmdk (snapshot)

E:\ExtraDrive\
  └── ESXi-Master-Disk3.vmdk (1TB, thick)

Why This Failed:
----------------
- Snapshot deletion requires consolidating delta disks into parent
- VMware expects parent and child in same directory
- Snapshot Manager doesn't handle cross-drive consolidation well
- Parent path references become invalid
- Manual intervention required to fix

================================================================================
DIAGNOSTIC PROCEDURES
================================================================================

Diagnosis 1: Check ESXi Datastore Status
-----------------------------------------
# SSH to ESXi Master (if management network still accessible)
ssh root@192.168.0.100

# Check datastore status
esxcli storage filesystem list

Problematic output:
Mount Point                                     Volume Name  UUID                                 Mounted  Type
----------------------------------------------  -----------  -----------------------------------  -------  ------
/vmfs/volumes/xxx                              NVME_DS_1    xxx-xxx-xxx                          false    VMFS

"Mounted: false" indicates datastore is inaccessible

Diagnosis 2: Check VM Power-On Failures
----------------------------------------
Try to power on a VM via ESXi Web UI:

Error message:
  "Cannot open the disk '/vmfs/volumes/NVME_DS_1/VM/VM.vmdk'"
  "Parent virtual disk has been modified since the child was created"

This confirms snapshot chain corruption.

Diagnosis 3: Verify VMDK Descriptor References
-----------------------------------------------
# From Windows host
notepad "C:\VMs\ESXi-Master\ESXi-Master-Disk2-00001.vmdk"

Look for:
  parentFileNameHint="D:/Overflow/ESXi-Master-Disk2.vmdk"

If parent path points to different drive/directory than child location,
chain is broken.

Diagnosis 4: Check VMware Workstation Snapshot Tree
----------------------------------------------------
Open VMware Workstation:
1. Select ESXi Master VM
2. VM > Snapshot > Snapshot Manager

If you see snapshots but cannot delete or revert, chain is corrupted.

Diagnosis 5: Verify File Locations
-----------------------------------
# Windows PowerShell
Get-ChildItem -Path "C:\VMs\ESXi-Master\" -Filter "*.vmdk" | Select Name, DirectoryName
Get-ChildItem -Path "D:\Overflow\" -Filter "*.vmdk" | Select Name, DirectoryName

If parent and child VMDKs are in different directories, you have the problem.

================================================================================
EMERGENCY RECOVERY PROCESS
================================================================================

WARNING: This is a risky recovery. BACKUP EVERYTHING before attempting.

Step 1: Assess the Damage
--------------------------
# SSH to ESXi Master (management network should still work)
ssh root@192.168.0.100

# Check which datastores are affected
esxcli storage filesystem list

# Attempt to browse datastore
ls /vmfs/volumes/NVME_DS_1/

If accessible via shell but not via UI, there's hope.

Step 2: Identify Parent and Child VMDKs
----------------------------------------
# From Windows host, list all VMDKs
Get-ChildItem -Recurse -Filter "*ESXi-Master*.vmdk" | Select FullName

Identify:
- Base disk (no numbers, e.g., ESXi-Master-Disk2.vmdk)
- Flat file (e.g., ESXi-Master-Disk2-flat.vmdk)
- Snapshots (e.g., ESXi-Master-Disk2-00001.vmdk)

Step 3: Copy Parent VMDKs to Same Folder as Children
-----------------------------------------------------
# From Windows PowerShell (Administrator)
# Copy parent VMDK from D:\Overflow to C:\VMs\ESXi-Master\

Copy-Item "D:\Overflow\ESXi-Master-Disk2.vmdk" -Destination "C:\VMs\ESXi-Master\"
Copy-Item "D:\Overflow\ESXi-Master-Disk2-flat.vmdk" -Destination "C:\VMs\ESXi-Master\"

Verify copy completed:
Get-ChildItem "C:\VMs\ESXi-Master\" | Where-Object Name -like "*Disk2*"

Step 4: Edit VMDK Descriptor Files
-----------------------------------
# Open child VMDK descriptor in text editor
notepad "C:\VMs\ESXi-Master\ESXi-Master-Disk2-00001.vmdk"

Find and fix parent reference:

Before:
  parentFileNameHint="D:/Overflow/ESXi-Master-Disk2.vmdk"

After:
  parentFileNameHint="ESXi-Master-Disk2.vmdk"

Save and close.

Repeat for all snapshot VMDK descriptors (00002.vmdk, 00003.vmdk, etc.)

Step 5: Update ESXi Master VMX File
------------------------------------
# Open VMX file
notepad "C:\VMs\ESXi-Master\ESXi-Master.vmx"

Find all disk references:
  scsi0:1.fileName = "D:/Overflow/ESXi-Master-Disk2.vmdk"

Change to:
  scsi0:1.fileName = "ESXi-Master-Disk2.vmdk"

Save and close.

Step 6: Restart VMware Services
--------------------------------
# From Windows PowerShell (Administrator)
Restart-Service -Name "VMware*"

Or restart VMware Workstation application.

Step 7: Restart ESXi Services
------------------------------
# SSH to ESXi Master
ssh root@192.168.0.100

# Restart hostd and vpxa services
/etc/init.d/hostd restart
/etc/init.d/vpxa restart

Wait 2-3 minutes for services to fully restart.

Step 8: Verify Datastore Access
--------------------------------
# From ESXi shell
esxcli storage filesystem list

Verify:
  Mounted: true

# Check datastore browser via ESXi Web UI
Navigate to Storage > Datastores > NVME_DS_1 > Browse

If you can browse files, recovery is progressing.

Step 9: Test VM Power-On
-------------------------
Attempt to power on a VM via ESXi Web UI.

If successful: Recovery complete (for now)
If failed: Check vmware.log for additional errors

Step 10: Consolidate Snapshots Carefully
-----------------------------------------
Once datastores are accessible:

1. In VMware Workstation Snapshot Manager
2. Delete snapshots ONE AT A TIME
3. Allow consolidation to complete fully before deleting next
4. Verify VMs still boot after each deletion
5. DO NOT delete multiple snapshots simultaneously

================================================================================
LONG-TERM FIX: STORAGE MIGRATION
================================================================================

This recovery is temporary. To prevent recurrence, consolidate storage properly.

Step 1: Create New Clean Datastores
------------------------------------
# In ESXi, create new VMFS datastores from clean VMDKs
# All VMDKs stored in C:\VMs\ESXi-Master\ (single location)

Planning:
- NVME_DS_1: 2TB, thin provisioned, for VMs
- NVME_DS_2: 2TB, thin provisioned, for NAS/ISOs

Step 2: Use Storage vMotion
----------------------------
For each VM on corrupted datastore:
1. Right-click VM > Migrate
2. Select "Change storage only"
3. Choose new clean datastore (NVME_DS_1)
4. Start migration
5. Verify VM boots after migration

Repeat for all VMs.

Step 3: Migrate ISO Library and Templates
------------------------------------------
Use Datastore Browser:
1. Download ISOs from old datastore
2. Upload to new datastore (NVME_DS_2)

Or use SCP from ESXi shell:
cp /vmfs/volumes/OLD_DS/ISOs/* /vmfs/volumes/NVME_DS_2/ISOs/

Step 4: Safely Unmount Old Datastores
--------------------------------------
After verifying all VMs migrated:

# In ESXi Web UI
Storage > Datastores > OLD_DS > Unmount

Wait for unmount to complete.

Step 5: Remove Old vDisks from ESXi Master
-------------------------------------------
1. Shutdown ESXi Master VM
2. VMware Workstation > Edit Settings
3. Remove old disk (D:\Overflow\ESXi-Master-Disk2.vmdk)
4. Add new disk if needed (in C:\VMs\ESXi-Master\)
5. Power on ESXi Master

Step 6: Delete Old VMDKs
-------------------------
# ONLY after verifying stability for 1+ week
# From Windows PowerShell
Remove-Item "D:\Overflow\ESXi-Master-Disk2*.vmdk"
Remove-Item "E:\ExtraDrive\ESXi-Master-Disk3*.vmdk"

This migration can take 6+ hours with full backups at each step.

================================================================================
REFINED DESIGN: PREVENT SNAPSHOT CORRUPTION
================================================================================

Storage Best Practices:
-----------------------
✅ All VMDKs in one folder - No broken links
✅ Consistent thin provisioning - No mixed types
✅ Clear naming convention - Purpose obvious from filename
✅ Planned capacity upfront - No ad-hoc additions
✅ Separate datastores by workload - Easier management

Example Correct Layout:
------------------------
C:\VMs\ESXi-Master\
  ├── ESXi-Master.vmx
  ├── ESXi-Master.vmdk
  ├── ESXi-Master-OS-150GB.vmdk (thin, ESXi boot disk)
  ├── ESXi-Master-NVME-DS1-2TB.vmdk (thin, VM storage)
  ├── ESXi-Master-NVME-DS2-2TB.vmdk (thin, NAS storage)
  └── vmware.log

All disks in same directory - snapshot consolidation will work.

Snapshot Management Rules:
---------------------------
✅ Maximum 2-3 snapshots at a time
✅ Delete snapshots after testing completes
✅ Never accumulate snapshots long-term
✅ One snapshot deletion at a time (allow consolidation to finish)
✅ Backup before risky snapshot operations
✅ Test VM boot after snapshot deletion
✅ Document snapshot purpose and expiration

================================================================================
PREVENTION
================================================================================

1. **Plan storage layout upfront**
   - Calculate total capacity needed
   - Allocate all disks at creation time
   - Keep all VMDKs in same folder

2. **Never scatter VMDKs across drives**
   - If you must add storage, use new datastores inside ESXi
   - Don't add VMDKs to ESXi Master VM stored on different drives

3. **Use thin provisioning consistently**
   - Don't mix thick and thin
   - Thin grows as needed, thick pre-allocates

4. **Snapshot discipline**
   - Create snapshots only when needed
   - Delete immediately after use
   - Never let snapshot chain exceed 3 levels
   - Consolidate regularly

5. **Backup strategy**
   - Export VMs before risky changes
   - Backup ESXi configuration
   - Weekly VM folder backup
   - Test restore procedures

6. **Documentation**
   - Document storage architecture
   - Track VMDK locations in LLD
   - Note which datastores are on which VMDKs

================================================================================
VERIFICATION
================================================================================

After implementing refined storage design:

Check 1: All VMDKs in One Location
-----------------------------------
Get-ChildItem "C:\VMs\ESXi-Master\" -Filter "*.vmdk" | Select DirectoryName

All should show: C:\VMs\ESXi-Master

Check 2: Datastore Status in ESXi
----------------------------------
esxcli storage filesystem list

All datastores should show: Mounted: true

Check 3: VM Power-On Test
--------------------------
Power on all VMs and verify they boot successfully.

Check 4: Snapshot Operations Work
----------------------------------
1. Create test snapshot
2. Make a small change
3. Revert to snapshot
4. Delete snapshot

All operations should complete without errors.

Check 5: No Mixed Provisioning
-------------------------------
Get-ChildItem "C:\VMs\ESXi-Master\" -Filter "*.vmdk" | Select Name

All VMDKs should be thin (or all thick, but not mixed).

================================================================================
BACKUP BEFORE RECOVERY
================================================================================

CRITICAL: Before attempting recovery, backup everything:

# Option 1: Copy entire VM folder (safest but slow)
robocopy "C:\VMs\ESXi-Master" "E:\BACKUP\ESXi-Master-Emergency" /MIR

# Option 2: Export VM (if possible)
VMware Workstation > File > Export to OVF

# Option 3: Copy just the VMDK files
Get-ChildItem "C:\VMs\ESXi-Master\" -Filter "*.vmdk*" | Copy-Item -Destination "E:\BACKUP\"

Recovery is risky. Having a backup means you can try multiple approaches.

================================================================================
IMPACT ANALYSIS
================================================================================

Data Loss Risk: CRITICAL
-------------------------
If recovery fails:
- Lose all VMs on affected datastores
- Lose 40+ hours of nested ESXi configuration
- Lose vCenter setup and integrations
- Lose DNS, NAS, and support VMs
- Lose custom scripts and automation

This is why the lesson is valuable: "It's just a lab" until you lose 3 weeks.

Time to Recover: 6-12 hours
----------------------------
- Emergency recovery: 2-4 hours (if successful)
- Storage migration: 6+ hours
- Verification and testing: 2+ hours
- Emotional recovery from near-disaster: Days

Prevention Time: 30 minutes
----------------------------
- Plan storage layout upfront: 15 minutes
- Follow snapshot discipline: Ongoing
- Weekly backups: 30 minutes/week

Prevention is 100x faster than recovery.

================================================================================
REFERENCES
================================================================================
Source: /DC-K8s/.archive/00-HOST-FOUNDATION/09-legacy-design-lessons.md
Related Cases:
  - Other storage cases in cases/storage/
Related Docs: Storage Configuration, LLD Documentation

VMware KB Articles:
  - "Consolidating snapshots fails with the error: Parent virtual disk has been modified"
  - "Understanding virtual disk files (VMDK)"

================================================================================
LESSONS LEARNED
================================================================================
- Ad-hoc storage growth creates technical debt
- Snapshot chains are fragile when VMDKs are scattered
- "It's just a lab" is not an excuse for no backups
- Proper planning prevents painful recovery
- Storage architecture decisions have long-term consequences
- Never accumulate more than 2-3 snapshots
- Test snapshot deletion in non-critical environment first
- Cross-drive VMDK references are a ticking time bomb
- Recovery procedures should be tested, not improvised
- Emotional cost of data loss is higher than time cost
- Good architecture is invisible; bad architecture causes disasters
- Documentation enables recovery; lack of it causes panic
