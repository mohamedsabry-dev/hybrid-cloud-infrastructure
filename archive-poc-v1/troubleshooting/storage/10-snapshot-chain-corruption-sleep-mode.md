━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TROUBLESHOOTING CASE: SNAPSHOT CHAIN CORRUPTION FROM LAPTOP SLEEP MODE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Category: Storage / VMware Workstation / Power Management / Snapshot Corruption
Severity: CRITICAL
Incident: Yes
Environment: VMware Workstation, Nested ESXi, NAS VM
Impact: System-wide instability, data accessibility loss, 1TB storage inflation
Status: Resolved

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PROBLEM DESCRIPTION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Issue: Catastrophic VMware Snapshot Chain Corruption After Laptop Sleep

Trigger Event:
  └── Laptop entered sleep mode during active Veeam backup operation
      ├── Time: ~5 PM during backup window
      ├── Active I/O: Veeam backup jobs reading from NAS VM
      └── Power State: Asus Armoury Crate overrode Windows power settings

Initial Symptoms:
  ├── Snapshot file inflation: 1TB snapshot created on thin-provisioned disk
  ├── Broken snapshot chain with missing delta files (000004, 000005, 000006)
  ├── VM performance degradation: CPU usage spiking to 9,000+ MHz
  ├── System-wide lag and unresponsiveness
  ├── Failed consolidation attempts: "Insufficient space" errors
  └── VMware UI "Consolidate" button non-functional


Environment Details:

Host System:
  ├── Gaming laptop running VMware Workstation
  ├── NVMe storage with nested virtualization
  ├── Asus performance management software (Armoury Crate)
  └── Issue: OEM software overriding Windows power settings

Affected VM - NAS Server:
  ├── Running on nested ESXi
  ├── Primary data disk: DS_NVME_02 (98.4GB base, thin-provisioned)
  ├── Snapshot chain state:
  │   ├── 000001.vmdk: 9.67GB
  │   ├── 000002.vmdk: 475MB
  │   ├── 000003.vmdk: 3.7GB
  │   ├── 000004.vmdk: MISSING (manually deleted)
  │   ├── 000005.vmdk: MISSING (manually deleted)
  │   └── 000006.vmdk: MISSING (manually deleted)
  └── Total corrupted state: ~114GB (from original 98.4GB thin)

Critical Error Messages:
```
snapshot.needConsolidate = "TRUE"
File not found: DS_NVME_02-000004.vmdk
Parent CID mismatch in descriptor
Insufficient space for consolidation
Disk Active Time: 88% sustained
Write throughput: 117MB/s (abnormal for idle system)
```

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ROOT CAUSE ANALYSIS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


The Failure Cascade:

1. Power Management Conflict (Initial Trigger)
   ├── Asus Armoury Crate "Performance Mode" active
   ├── Software silently overrode Windows power settings
   ├── Laptop entered sleep during active I/O operations
   ├── Veeam backup job was reading from NAS VM disks
   └── VMware Workstation did not gracefully suspend nested VMs

2. Incomplete Snapshot Merge
   ├── VMware initiated automatic snapshot consolidation
   ├── Sleep mode interrupted merge operation mid-process
   ├── Partial writes to delta files created inconsistent state
   ├── Snapshot metadata corrupted during forced suspension
   └── Left orphaned delta files in broken chain

3. Metadata Corruption & Thin Disk Inflation
   ├── Snapshot metadata bloated during interrupted merge
   ├── VMware protection mechanism triggered
   ├── Thin-provisioned disk force-expanded to full 1TB
   ├── Purpose: Prevent data loss from corrupt metadata
   └── Result: 98.4GB disk → 1TB, consuming all available space

4. I/O Latency Stacking
   ├── System attempting automatic recovery on wake
   ├── Simultaneously processing zombie snapshot references
   ├── CPU overcommit: 9,000+ MHz trying to consolidate
   ├── Disk queue saturation: 88% active time, 117MB/s writes
   └── Entire nested environment became unresponsive

5. Manual Intervention (User Error)
   ├── User panic-deleted snapshot files 000004, 000005, 000006
   ├── Goal: Reclaim disk space quickly
   ├── Result: Broke snapshot chain continuity permanently
   ├── VMware could no longer perform automatic consolidation
   └── VM boot validation failing due to missing chain links

Why This Is Particularly Dangerous in Nested Environments:

Nested Virtualization Complexity:
  ├── Layer 1: Windows Host
  ├── Layer 2: VMware Workstation
  ├── Layer 3: ESXi Master VM
  ├── Layer 4: ESXi Nested VM (Production)
  └── Layer 5: Guest VMs (NAS affected)

  Sleep propagation:
    Windows sleep → VMware suspend → ESXi panic → Guest I/O freeze

Thin Provisioning Risk Multiplication:
  ├── Host VMDK: Thin provisioned
  ├── Nested ESXi datastore: Thin provisioned
  ├── Guest VM disk: Thin provisioned
  └── Snapshot corruption at any layer → cascading failure

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RESOLUTION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Phase 1: Immediate Stabilization & System Access

Step 1: Prevent Further Corruption
  Actions:
    ├── Disable laptop sleep mode in Windows Power Settings
    ├── Configure "Lid Close" action: NEVER sleep when plugged in
    ├── Disable Asus Armoury Crate automatic power profile switching
    └── Set performance mode to "Best Performance" (fixed)

  Commands (Windows):
    powercfg /change standby-timeout-ac 0
    powercfg /change monitor-timeout-ac 30

  Verification:
    Yes Power settings persist after reboot
    Yes Armoury Crate no longer overrides settings
    Yes Laptop stays on during I/O operations

Step 2: Temporary VM Boot Access
  Problem: VM won't boot due to missing snapshot 000006

  Workaround:
    ├── Navigate to VM directory: F:\ESXI_Master\
    ├── Rename existing file:
    │     copy DS_NVME_02-000003.vmdk DS_NVME_02-000006.vmdk
    ├── Purpose: Satisfy VMware's file validation check
    └── WARNING: Temporary only, does NOT fix corruption

  Result: VM boots but performance severely degraded

Phase 2: Disk Consolidation (The Fix)

Step 1: Use vmware-vdiskmanager to Merge Snapshots

  Navigate to VMware Workstation installation:
    cd "C:\Program Files (x86)\VMware\VMware Workstation"

  Execute disk consolidation:
    .\vmware-vdiskmanager.exe -r "F:\ESXI_Master\DS_NVME_02-000003.vmdk" -t 0 "F:\ESXI_Master\DS_NVME_02_NEW.vmdk"

  Parameters Explained:
    -r <source>  : Read and merge snapshot chain
    -t 0         : Output type 0 (single growable virtual disk)
    <target>     : New consolidated disk path

  Progress Monitoring:
    ├── Process duration: ~15-20 minutes
    ├── Reads all delta files (000001, 000002, 000003)
    ├── Merges changes into single VMDK
    └── Output: 250MB thin-provisioned disk (grows to max 98.4GB)

  Important Notes:
     Requires PowerShell prefix .\ to execute binaries in current directory
     Ensure sufficient space on target drive (need 2× disk size free)
     Do NOT interrupt this process (close lid, sleep, shutdown)

Step 2: Verify Consolidated Disk Integrity

  Check output files:
    dir "F:\ESXI_Master\DS_NVME_02_NEW*"

  Expected results:
    ├── DS_NVME_02_NEW.vmdk (descriptor file)
    ├── DS_NVME_02_NEW-flat.vmdk (data file, ~250MB)
    └── No snapshot delta files

  Validation:
    Yes File size reasonable (not 1TB)
    Yes Descriptor file readable
    Yes No errors in vmware.log

Phase 3: ESXi Datastore Recovery

Problem: ESXi detects consolidated disk as "snapshot LUN" due to UUID mismatch

Step 1: List Unmounted Volumes via ESXi SSH

  Command:
    esxcfg-volume -l

  Output shows:
    VMFS UUID: <uuid>
    Device: /vmfs/devices/disks/mpx.vmhba0:C0:T2:L0:1
    Status: unmounted (snapshot LUN)

Step 2: Force Resignature and Mount

  Command:
    esxcfg-volume -r DS_NVME_02

  What This Does:
    ├── Assigns new VMFS UUID to datastore
    ├── Preserves all data on disk
    ├── Mounts datastore to /vmfs/volumes/
    └── Makes VMs accessible again

  Verification:
    ls /vmfs/volumes/ | grep DS_NVME_02

  Result:
    Yes Datastore visible in vSphere/vCenter
    Yes All VMs show in inventory
    Yes Can browse datastore files

Phase 4: VM Reconfiguration

Step 1: Remove Broken Disk from VM

  Via vSphere Client:
    ├── Edit VM Settings → NAS VM
    ├── Locate old disk: DS_NVME_02-000003.vmdk
    ├── Select disk → Remove
    ├── IMPORTANT: Choose "Remove from virtual machine" (not "Delete from disk")
    └── Save changes

Step 2: Attach Consolidated Disk

  Via vSphere Client:
    ├── Edit VM Settings → Add → Hard Disk
    ├── Select "Use an existing virtual disk"
    ├── Browse to: DS_NVME_02_NEW.vmdk
    ├── When prompted: Select "I Moved It"
    │     └── Preserves MAC addresses and VM identity
    └── Save changes

Step 3: Clean Snapshot Metadata

  Via ESXi SSH:
    cd /vmfs/volumes/DS_NVME_02/NAS/
    rm NAS.vmsd

  Purpose:
    ├── Forces VMware to rebuild snapshot database
    ├── Clears "needsConsolidate" flag
    └── Removes references to deleted snapshots

  Verification:
    vim NAS.vmx

  Ensure no snapshot references:
    # Should NOT contain:
    snapshot.numSnapshots = "X"
    snapshot.current = "X"

Step 4: Power On VM

  Command:
    vim-cmd vmsvc/power.on <vmid>

  Result:
    Yes VM boots successfully
    Yes No consolidation warnings
    Yes All data accessible
    Yes Performance normalized

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
POST-RESOLUTION VALIDATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Cleanup Actions:

Space Reclaimed:
  ├── Deleted broken snapshot files: 000001, 000002, 000003
  ├── Removed original base disk: DS_NVME_02.vmdk
  └── Total space recovered: ~110GB

Performance Validation:
  ├── CPU usage: Returned to normal levels (no more 9,000 MHz spikes)
  ├── Disk latency: Stabilized below 2ms
  ├── Network throughput: Stable at expected 250MB/s
  └── Data loss: Only gap between 5 PM - 6 PM on day of incident

Preventive Measures Implemented:

1. Power Management:
   ├── Configured "Lid Close" and "Sleep" to NEVER when plugged in
   ├── Set Asus performance mode to "Best Performance" profile
   └── Verified settings persist across reboots

2. Backup Strategy:
   ├── Implemented 10-minute gap between Veeam backup jobs
   ├── Recommended Direct Storage Access (DSA) over HotAdd mode
   └── Daily manual check for "Needs Consolidation" warnings

3. Storage Configuration:
   ├── Set data disk to "Independent-Persistent" mode
   └── Prevents snapshot chain formation on critical data volumes

4. Disaster Recovery:
   ├── Full VM partition backup on external 2TB NVMe
   └── Code synchronized to GitHub before shutdown events

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
LESSONS LEARNED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Critical Insights:

1. Gaming Laptop Power Management Is Unreliable
   "OEM power management software (Asus Armoury Crate, Dell Power Manager, etc.)
   can silently override Windows power settings. For critical lab environments,
   you MUST disable OEM power profiles AND set Windows power settings to NEVER
   sleep when plugged in."

2. Never Delete Snapshot Files Manually
   No Deleting snapshot delta files (000001.vmdk, 000002.vmdk, etc.)
   Yes ALWAYS use VMware tools: vmware-vdiskmanager or vSphere consolidation
   Yes Manual deletion breaks the chain and makes automatic recovery impossible

3. Thin Provisioning Can Inflate as Protection Mechanism
   "When VMware detects snapshot metadata corruption, it force-expands
   thin-provisioned disks to their FULL maximum size as a data protection
   measure. A 100GB thin disk can instantly become 1TB."

4. Nested Virtualization Amplifies Sleep Mode Risks
   No Hardware sleep during I/O is catastrophic in nested environments
   Yes Sleep propagates through all virtualization layers
   Yes Each layer has different suspend timing, causing race conditions

5. PowerShell Execution Context Matters
   "To execute vmware-vdiskmanager.exe from PowerShell, you MUST use the .\
   prefix even when in the program's directory."

6. Independent Disk Mode Prevents Snapshot Chains
   "Setting data disks to 'Independent-Persistent' mode excludes them from
   VMware snapshots entirely. Essential for VMs with large data volumes."

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TOOLS REFERENCE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

vmware-vdiskmanager.exe:
  Location: C:\Program Files (x86)\VMware\VMware Workstation\

  Consolidate snapshots:
    .\vmware-vdiskmanager.exe -r source.vmdk -t 0 target.vmdk

  Defragment disk:
    .\vmware-vdiskmanager.exe -d disk.vmdk

  Expand disk:
    .\vmware-vdiskmanager.exe -x 200GB disk.vmdk

ESXi Storage Commands:
  List volumes:       esxcfg-volume -l
  Mount/resignature:  esxcfg-volume -r <datastore_name>
  List datastores:    esxcli storage filesystem list
  Datastore info:     vmkfstools -P /vmfs/volumes/<datastore>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FINAL OUTCOME
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

- VM fully operational with zero data loss (except 1-hour window)
- Performance restored to baseline levels
- 110GB storage space reclaimed
- Preventive measures implemented
- Power management conflicts resolved
- Snapshot chain permanently fixed

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RELATED DOCUMENTATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

VMware Knowledge Base:
  • VMware KB: Snapshot consolidation fails with "insufficient space"
  • VMware KB: Resignaturing VMFS datastores
  • VMware KB: Independent disk modes for backup exclusion
  • VMware KB: Using vmware-vdiskmanager

Related Cases:
  • Case #08: VMware Snapshot Chain Corruption
  • Case #09: Thick Provisioned Snapshot Size
  • Windows Host Sleep Mode Network Failures
  • NAS Memory Starvation (backup resource pressure)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

