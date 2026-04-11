# TS-PVE-015 | 2026-04-11 | UNRESOLVED

> **REAL INCIDENT** — This case occurred during an unplanned production failure (Proxmox host crash during backup), not planned DR testing. Documented before DR test phase began.

## 1. Context
- System: Proxmox VE (pve-dev) - ASUS laptop used as server
- Environment: pve-dev
- Related components: vzdump backup job, LXC containers, NFS storage (nas-dev-data), LVM thin pool

## 2. Issue
- Symptom: Proxmox host crashed silently during scheduled backup job while backing up CT 2006 (vault3). No error logged, system just rebooted.
- Error:
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

**Impact:**
- CT 2006 left in locked state (snapshot-delete)
- vzdump snapshot not cleaned up
- Backup job interrupted, email notification not sent
- All VMs/LXCs restarted after reboot

## 3. Analysis

### Timeline Reconstruction

```
10:52:46  Backup job started (vzdump --all --mode snapshot --compress zstd)
10:52:46  Starting Backup of VM 1001 (qemu) - completed OK
10:54:02  Starting Backup of VM 1010-1012 (k8s masters) - completed OK
10:57:41  Starting Backup of VM 1020-1022 (k8s workers) - completed OK
10:59:54  Starting Backup of CT 2001-2005 (LXCs) - completed OK
11:01:18  Starting Backup of CT 2006 (vault3)
11:01:18  LVM snapshot created with thin pool warnings
11:01:18  Writing vzdump archive to NAS...
     ↓
     1.6GiB written at 175MiB/s
     ↓
     SYSTEM CRASH - No further logs
     ↓
11:01:xx  System rebooted (hard crash, no shutdown sequence)
```

### What Was Checked

**System reboot history:**
```bash
last -x | head -5
# reboot   system boot  6.17.9-1-pve  Sat Apr 11 11:01 - still running
# reboot   system boot  6.17.9-1-pve  Sat Apr 11 10:31 - crash

wtmpdb last reboot
# Sat Apr 11 10:31 - crash   (confirmed hard crash, not graceful shutdown)
```

**Kernel logs from crashed boot:**
```bash
journalctl -b -1 --no-pager | tail -50
# Shows normal backup operations
# No panic, OOM, or hardware error logged
# Logs end mid-operation
```

**Hardware errors:**
```bash
dmesg | grep -i "mce\|hardware error"
# MCE: In-kernel MCE decoding enabled (no actual errors)

journalctl -b -1 | grep -i "panic\|oops\|bug:"
# No kernel panic found
```

**NFS/Storage:**
```bash
nfsstat -c
# 0 retransmissions - NFS healthy

mount | grep nas
# NFS mounts present and working
```

### What Was NOT Found

| Investigation | Result |
|---------------|--------|
| Kernel panic | No panic logged |
| OOM killer | No OOM events |
| Hardware MCE | No hardware errors |
| NFS timeout | No NFS errors, 0 retrans |
| Watchdog trigger | No watchdog message |
| Disk errors | No I/O errors |
| Power events | No ACPI shutdown logged |

### Observations

**Thin pool overprovisioning warnings:**
- Sum of thin volumes: ~350 GiB
- Available space in VG: ~121 GiB
- Warnings present but previous backups (2001-2005) completed successfully with same warnings

**Suspend attempts during backup (noise, not cause):**
```
systemd-logind[851]: Suspending...
systemd-logind[851]: Unit suspend.target is masked, refusing operation.
```
- Something triggers suspend events repeatedly (lid sensor?)
- Suspend is properly masked and blocked
- Not the crash cause since this happened throughout and system kept running

**asus_wmi unknown key code:**
```
Apr 11 10:58:35 pve-dev kernel: asus_wmi: Unknown key code 0x6d
```
- Appeared shortly before crash
- Unknown what this key code represents

### Suspected Causes (Unconfirmed)

1. **Thermal shutdown** - Laptop may have overheated during I/O intensive backup (zstd compression)
2. **Thin pool metadata exhaustion** - Despite data warnings, metadata could have filled
3. **USB storage interface issue** - stor0 is USB ethernet to NAS
4. **ACPI hardware event** - Unknown key code 0x6d or other hardware trigger
5. **Kernel lockup** - I/O deadlock without logged panic

Cannot confirm any cause - crash was completely silent at OS level.

## 4. Root Cause
> **UNDETERMINED** - System crashed without any logged error during vzdump backup of CT 2006. The crash occurred while writing backup archive to NFS storage. No kernel panic, OOM, hardware error, or shutdown sequence captured. This was a hard crash at hardware/firmware level that bypassed OS logging.

## 5. Solution
> **LXC container recovery performed:**

```bash
# 1. Check for stuck Proxmox snapshots (not LVM)
pct listsnapshot 2006
# Output showed:
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
# Output: `-> current   You are here!

# 5. Start the container
pct start 2006
```

**Note:** The LVM-level snapshots (`snap_vm-2006-disk-*_vzdump`) were automatically cleaned up during reboot. Only the Proxmox-level snapshot metadata remained stuck, requiring `pct delsnapshot` to clean up.

System came back up after crash, all VMs/LXCs restarted via autostart. CT 2006 required manual unlock and snapshot cleanup before starting.

## 6. Solution Risk
- Risk level: N/A (recovery only, root cause unresolved)
- Potential impact: Issue may recur on next backup

## 7. Impact After Fix
- Observed: CT 2006 unlocked and running
- Vault cluster operating with 2 nodes (vault3 was down during crash)
- Kubernetes unaffected (see TS-K8S-024)
- No data loss confirmed

## 8. Notes

### Crash Pattern

Multiple crashes in recent history:
```
Sat Apr 11 10:31 - crash
Thu Apr  9 09:40 - crash
```

Both during high I/O operations. Suggests hardware-related issue with this laptop server.

### Prevention Considerations

| Approach | Benefit | Effort |
|----------|---------|--------|
| Monitor thermals during backup | Identify thermal issues | Low |
| Add cooling for laptop | Prevent thermal shutdown | Low |
| Enable kdump | Capture kernel panics | Medium |
| Reduce zstd compression level | Lower CPU load | Low |
| Schedule backups at cooler times | Reduce thermal stress | Low |
| Disable lid sensor completely | Prevent ACPI events | Low |
| Address thin pool overprovisioning | Remove warnings | Medium |

### Commands for Future Investigation

If this recurs, capture immediately:
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

### Related Cases
- TS-K8S-024: Vault cluster resilience during this outage
- TS-VAULT-005: Vault node recovery after crash (stale Raft data issue)
- TS-PVE-008: LVM thin pool resize (related to overprovisioning warnings)
- TS-PVE-014: Worker VM crash unknown cause (different incident, similar pattern)

## 9. Workaround (if any)
> Monitor system closely during next backup job. Consider:
> - Running `watch -n 1 'cat /sys/class/thermal/thermal_zone*/temp'` during backup
> - Temporarily reducing backup compression level
> - Checking laptop ventilation and cooling
