━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TROUBLESHOOTING CASE #03: DISK RACE CONDITION DISASTER (/dev/sdX SWAP)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Category: Storage / Linux System Configuration
Severity: CRITICAL
Environment: NAS VM (Linux)
Source: Draft for Storage (Lines 543-626)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PROBLEM DESCRIPTION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Issue: ALL Internal VMs Disconnected and Could Not Start

Discovery:
  └── "One day, opened the laptop, started the environment → ALL internal VMs
      disconnected and could not start."

Investigation Results:

vCenter Datastores:
  ├── NAS_DS_1: Shows 5GB capacity (WRONG - should be 900GB!)
  ├── NAS_DS_2: Shows 900GB capacity (WRONG - should be 5GB!)
  ├── VM files: All located on NAS_DS_2
  └── vCenter Events: No errors or warnings recorded

NAS VM Direct Check:
  ├── Command: df -h
  │     Result: Both /mnt/shared_storage and /mnt/datastor2 exist
  │             BUT storage sizes are crossed!
  │
  ├── Command: lsblk
  │     Result: /dev/sdb = 5GB (should be 900GB!)
  │             /dev/sdc = 900GB (should be 5GB!)
  │
  └── Realization: THE DISKS SWAPPED DEVICE NAMES!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ROOT CAUSE ANALYSIS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Hardware Race Condition:

Problem:
  └── Using /dev/sdX instead of UUID in /etc/fstab

Original /etc/fstab Configuration (WRONG):
  # 900GB Production Storage
  /dev/sdb /mnt/shared_storage  ext4  defaults  0 0

  # 5GB Heartbeat Storage
  /dev/sdc /mnt/datastor2       ext4  defaults  0 0

Linux Behavior:
  ├── Linux assigns /dev/sdX names based on initialization order
  ├── Race Condition: Whichever disk initializes first gets /dev/sdb
  ├── Result: After reboot, disks came up in opposite order
  └── Impact: Mounts crossed - production storage mounted as heartbeat and vice versa

Why It Happened:
  "To be honest, I saw guides saying use UUID and some using /dev/sdx directly.
  I was lazy to run the blkid command to get the UUID and use it, so I went
  with the easy way which caused us disaster later."

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CRITICAL WARNING ABOUT /etc/fstab
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠️  CRITICAL:
  "This file is checked on VM boot. If it has errors or typos, the VM will
  NOT start. Always test before rebooting."

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RECOVERY PROCEDURE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Step 1: Get Correct UUIDs
  Command:
    sudo blkid

  Output Example:
    /dev/sdb: UUID="550e8400-e29b-41d4-a716-446655440000" TYPE="ext4"
    /dev/sdc: UUID="12345678-abcd-1234-5678-1234567890ab" TYPE="ext4"

Step 2: Update /etc/fstab with UUID-based Mounts

  Correct Configuration:
    # ============================================
    # NFS STORAGE - PERSISTENT UUID MOUNTING
    # ============================================
    # Production Storage (900GB) - Use YOUR actual UUID from blkid
    UUID=550e8400-e29b-41d4-a716-446655440000  /mnt/shared_storage  ext4  defaults  0 0

    # Heartbeat Storage (5GB) - Use YOUR actual UUID from blkid
    UUID=12345678-abcd-1234-5678-1234567890ab  /mnt/datastor2       ext4  defaults  0 0

Step 3: Validate /etc/fstab BEFORE Rebooting
  Command:
    sudo findmnt --verify

  Expected: No errors reported

  ⚠️  If errors found, DO NOT reboot - fix them first!

Step 4: Reboot and Verify
  ├── Reboot NAS VM
  ├── Verify mounts: df -h
  └── Result: All storage back to normal, VMs operational

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
LESSONS LEARNED - PRODUCTION BEST PRACTICES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

"If you are planning for production-grade or even lab testing-grade environments,
ALWAYS make sure that the configuration you are doing follows best practices
to avoid planting issues for the future of the environment."

Why UUID is Critical:
  ✓ UUID is permanent identifier tied to filesystem
  ✓ Device names (/dev/sdX) are dynamic and assigned at boot time
  ✓ Multi-disk systems MUST use UUID for reliable mounting
  ✓ Race conditions are unpredictable - may work for months, then fail

Key Takeaways:
  ✗ NEVER use /dev/sdX device names in /etc/fstab for multi-disk systems
  ✓ ALWAYS use UUID for persistent mount points
  ✓ ALWAYS validate /etc/fstab with findmnt --verify before rebooting
  ✓ Taking the "easy way" with critical infrastructure = future disaster
  ✓ Best practices exist for a reason - they prevent race conditions

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PREVENTION MEASURES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

System Configuration:
  ✓ Use UUID-based mounting for all persistent disks
  ✓ Use /dev/sdX ONLY for temporary/removable devices
  ✓ Document UUID assignments in configuration comments
  ✓ Test /etc/fstab changes in staging first

Validation Process:
  ✓ Always run `findmnt --verify` after editing /etc/fstab
  ✓ Test in single-user mode if possible
  ✓ Keep backup of working /etc/fstab
  ✓ Never reboot without validation

Operational:
  ✓ Document all mount points with purpose
  ✓ Use descriptive comments in /etc/fstab
  ✓ Include UUID discovery commands in documentation
  ✓ Regular audit of mount configurations

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DETECTION & MONITORING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Early Warning Signs:
  ├── Unexpected datastore capacity changes
  ├── VMs reporting wrong disk sizes
  ├── NFS mount errors on client VMs
  └── Storage performance degradation

Health Check Commands:
  ├── Verify mount points: df -h
  ├── Check device assignments: lsblk
  ├── Verify UUIDs: blkid
  └── Check fstab consistency: findmnt --verify

Automated Monitoring:
  ├── Monitor datastore capacity trends
  ├── Alert on unexpected capacity changes
  ├── Validate mount points after reboot
  └── Check NFS export availability

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RELATED ISSUES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  • Linux mount configuration best practices
  • NFS export configuration reliability
  • ESXi datastore connectivity issues

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
