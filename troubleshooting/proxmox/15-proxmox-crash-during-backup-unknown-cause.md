# TS-PVE-015 | 2026-04-11 | UNRESOLVED
_____________________________________________________________________

[Info]
Domain: Proxmox VE / vzdump backup / Hardware
Sub-techs: vzdump backup job, LXC containers, NFS storage (nas-dev-data), LVM thin pool, ASUS laptop server
Environment: pve-dev
Re-opened: No

_____________________________________________________________________

[Issue Description]
REAL INCIDENT -- occurred during unplanned production failure, not planned DR testing.

Proxmox host crashed silently during scheduled backup job while backing up CT 2006 (vault3). No error logged, system just rebooted.

```
# Last entries in vzdump task log before crash
INFO: Starting Backup of VM 2006 (lxc)
INFO: Backup started at 2026-04-11 11:01:18
INFO: status = running
INFO: CT Name: vault3
INFO: including mount point rootfs ('/') in backup
INFO: including mount point mp0 ('/opt/vault') in backup
INFO: backup mode: snapshot
INFO: ionice priority: 7
INFO: suspend vm to make snapshot
INFO: create storage snapshot 'vzdump'
  Logical volume "snap_vm-2006-disk-0_vzdump" created.
  WARNING: Sum of all thin volume sizes (<345.03 GiB) exceeds the size of thin pool pve/data and the amount of free space in volume group (<121.69 GiB).
  Logical volume "snap_vm-2006-disk-1_vzdump" created.
  WARNING: Sum of all thin volume sizes (<350.03 GiB) exceeds the size of thin pool pve/data and the amount of free space in volume group (<121.69 GiB).
INFO: resume vm
INFO: guest is online again after 1 seconds
INFO: creating vzdump archive '/mnt/pve/nas-dev-data/dump/vzdump-lxc-2006-2026_04_11-11_01_18.tar.zst'
INFO: Total bytes written: 1683906560 (1.6GiB, 175MiB/s)
# LOG ENDS ABRUPTLY HERE - SYSTEM CRASHED
```

Impact: CT 2006 left in locked state (snapshot-delete), vzdump snapshot not cleaned up, backup job interrupted.

_____________________________________________________________________

[Analysis]
# Step 1: Timeline reconstruction
```
10:52:46  Backup job started (vzdump --all --mode snapshot --compress zstd)
10:52:46  Starting Backup of VM 1001 (qemu) - completed OK
10:54:02  Starting Backup of VM 1010-1012 (k8s masters) - completed OK
10:57:41  Starting Backup of VM 1020-1022 (k8s workers) - completed OK
10:59:54  Starting Backup of CT 2001-2005 (LXCs) - completed OK
11:01:18  Starting Backup of CT 2006 (vault3)
11:01:18  LVM snapshot created with thin pool warnings
11:01:18  Writing vzdump archive to NAS...
     1.6GiB written at 175MiB/s
     SYSTEM CRASH - No further logs
11:01:xx  System rebooted (hard crash, no shutdown sequence)
```

# Step 2: Check system reboot history
```bash
last -x | head -5
# reboot   system boot  6.17.9-1-pve  Sat Apr 11 11:01 - still running
# reboot   system boot  6.17.9-1-pve  Sat Apr 11 10:31 - crash

wtmpdb last reboot
# Sat Apr 11 10:31 - crash   (confirmed hard crash, not graceful shutdown)
```

# Step 3: Check kernel logs from crashed boot
```bash
journalctl -b -1 --no-pager | tail -50
# Shows normal backup operations, no panic, OOM, or hardware error logged
# Logs end mid-operation
```

# Step 4: Check hardware errors
```bash
dmesg | grep -i "mce\|hardware error"
# MCE: In-kernel MCE decoding enabled (no actual errors)

journalctl -b -1 | grep -i "panic\|oops\|bug:"
# No kernel panic found
```

# Step 5: Check NFS/Storage
```bash
nfsstat -c
# 0 retransmissions - NFS healthy

mount | grep nas
# NFS mounts present and working
```

# Step 6: What was NOT found

| Investigation | Result |
|---------------|--------|
| Kernel panic | No panic logged |
| OOM killer | No OOM events |
| Hardware MCE | No hardware errors |
| NFS timeout | No NFS errors, 0 retrans |
| Watchdog trigger | No watchdog message |
| Disk errors | No I/O errors |
| Power events | No ACPI shutdown logged |

# Step 7: Noise vs signal
Suspend attempts during backup (not the cause):
```
systemd-logind[851]: Suspending...
systemd-logind[851]: Unit suspend.target is masked, refusing operation.
```
Something triggers suspend events (lid sensor?) but suspend is properly masked.

asus_wmi unknown key code appeared shortly before crash:
```
Apr 11 10:58:35 pve-dev kernel: asus_wmi: Unknown key code 0x6d
```

# Step 8: Crash pattern
Multiple crashes in recent history:
```
Sat Apr 11 10:31 - crash
Thu Apr  9 09:40 - crash
```
Both during high I/O operations. Suggests hardware-related issue with this laptop server.

_____________________________________________________________________

[Final Root Cause]
UNDETERMINED -- system crashed without any logged error during vzdump backup of CT 2006. The crash occurred while writing backup archive to NFS storage. No kernel panic, OOM, hardware error, or shutdown sequence captured. This was a hard crash at hardware/firmware level that bypassed OS logging. Suspected causes include thermal shutdown (laptop under I/O load with zstd compression), thin pool metadata exhaustion, USB storage interface issue, or ACPI hardware event.

_____________________________________________________________________

[Final Solution]
Recovery only -- root cause unresolved.

I recovered CT 2006 from the stuck state:
```bash
# 1. Check for stuck Proxmox snapshots
pct listsnapshot 2006
# `-> vzdump                      2026-04-11 11:01:18     vzdump backup snapshot
#  `-> current                                            You are here!

# 2. Unlock the container (was in snapshot-delete state)
pct unlock 2006

# 3. Delete the stuck vzdump snapshot
pct delsnapshot 2006 vzdump --force
# Note: LVM snapshots were already cleaned up during reboot
# Output: lvremove snapshot 'pve/snap_vm-2006-disk-1_vzdump' error: Failed to find logical volume

# 4. Verify snapshot removed
pct listsnapshot 2006
# `-> current   You are here!

# 5. Start the container
pct start 2006
```

The LVM-level snapshots were automatically cleaned up during reboot. Only the Proxmox-level snapshot metadata remained stuck.

For future investigation if it recurs:
```bash
# Check thermals
cat /sys/class/thermal/thermal_zone*/temp
cat /sys/class/thermal/thermal_zone*/trip_point_*_temp

# Check thin pool
lvs -o+data_percent,metadata_percent pve/data

# Check USB ethernet
dmesg | grep -i "usb\|cdc_ncm\|stor0"

# Check NFS health
nfsstat -c
mount | grep nfs
```

Verified: Yes -- CT 2006 unlocked and running. Vault cluster recovered. No data loss confirmed. Root cause still open.

_____________________________________________________________________

[Risk Level] N/A (recovery only, root cause unresolved -- issue may recur)

_____________________________________________________________________

[References]
- Related: TS-K8S-024 (Vault cluster resilience during this outage)
- Related: TS-VAULT-005 (Vault node recovery after crash -- stale Raft data issue)
- Related: TS-PVE-008 (LVM thin pool resize -- related to overprovisioning warnings)
- Related: TS-PVE-014 (Worker VM crash unknown cause -- different incident, similar pattern)
