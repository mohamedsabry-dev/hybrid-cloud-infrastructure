# TS-PVE-010 | 2026-03-26 | RESOLVED

## 1. Context
- System: Proxmox VE with NFS backup storage
- Environment: Dev environment - Multiple VM restores from NFS backup storage
- Related components: vzdump, qmrestore, NFS storage (stor0), LVM thin pool

## 2. Issue
- Symptom: VM restore operations stuck at 100% for 10+ minutes, multiple restore operations started simultaneously (6 VMs)
- Error:
```
Logical Volume "vm-1012-cloudinit" already exists in volume group "pve"
```

**Additional symptoms:**
- Proxmox Web UI shows restore task "running" but no progress
- User cancelled stuck tasks, leaving orphaned LVM volumes
- Subsequent restore attempts failed with LVM errors

## 3. Analysis

### What Happened

When 6 VM restore operations were started simultaneously:
1. NFS storage (stor0) became I/O bottleneck
2. Restore processes competed for NFS bandwidth
3. Operations stalled waiting for NFS responses
4. User cancelled stuck tasks mid-operation
5. LVM volumes created but not cleaned up (orphaned)

### Evidence from Task Logs

```
6 concurrent qmrestore operations started
4 failed with "unexpected status" (cancelled)
2 qmstart failed with "received interrupt"
```

## 4. Root Cause
> Too many concurrent restore operations overwhelmed NFS storage. Cancelling stuck tasks mid-operation left orphaned LVM volumes that blocked subsequent restore attempts.

## 5. Solution
> Cancel stuck tasks, remove orphaned LVM volumes, retry restore sequentially.

### Step 1: Cancel Stuck Tasks

From Proxmox Web UI:
- Task View → Select stuck task → Stop

Or from CLI:
```bash
# List running tasks
pvesh get /cluster/tasks

# Stop specific task
pvesh delete /nodes/<node>/tasks/<upid>
```

### Step 2: Identify Orphaned LVM Volumes

```bash
# List all LVM volumes for the affected VM
lvs | grep vm-1012
```

**Output:**
```
vm-1012-cloudinit  pve  -wi-a-----   4.00m
vm-1012-disk-0     pve  -wi-a-----  32.00g
```

### Step 3: Remove Orphaned Volumes

```bash
# Remove cloudinit volume
lvremove -f pve/vm-1012-cloudinit

# Remove disk volume
lvremove -f pve/vm-1012-disk-0
```

**For multiple VMs:**
```bash
# VM 1012
lvremove -f pve/vm-1012-cloudinit
lvremove -f pve/vm-1012-disk-0

# VM 1022
lvremove -f pve/vm-1022-cloudinit
lvremove -f pve/vm-1022-disk-0

# Repeat for other affected VMs
```

### Step 4: Retry Restore Sequentially

```bash
# Restore one VM at a time
qmrestore /mnt/pve/stor0/dump/vzdump-qemu-1012-*.vma.zst 1012

# Wait for completion, then next
qmrestore /mnt/pve/stor0/dump/vzdump-qemu-1022-*.vma.zst 1022
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact: Data loss if wrong LVM volumes removed. Always verify VMID before `lvremove`.

## 7. Impact After Fix
- Observed: VMs restored successfully with sequential approach
- No more LVM conflicts
- Restore time predictable (one at a time)

## 8. Notes

### Recommended Concurrent Operations

| Restore Type | Recommended Max Concurrent |
|--------------|---------------------------|
| NFS storage  | 2-3 VMs                   |
| Local storage| 4-5 VMs                   |
| NVMe storage | 6-8 VMs                   |

### Best Practices

1. **Restore sequentially** - Start next restore only after previous completes
2. **Monitor NFS I/O** - Watch for bottlenecks during restore
3. **Use local storage** - If available, restore to local LVM first, then migrate
4. **Schedule restores** - Use off-peak hours for bulk restores
5. **Check disk space** - Ensure sufficient space before starting

### Recovery Checklist

If restore hangs:

- [ ] Wait 5 minutes (may be slow, not stuck)
- [ ] Check NFS connectivity: `ping <nfs-server>`
- [ ] Check NFS I/O: `nfsiostat 1`
- [ ] If truly stuck, cancel task from UI
- [ ] List orphaned LVM: `lvs | grep vm-<VMID>`
- [ ] Remove orphaned LVM: `lvremove -f pve/vm-<VMID>-*`
- [ ] Retry restore individually

### Commands Reference

```bash
# List volumes for specific VM
lvs | grep vm-<VMID>

# Remove specific volume (force)
lvremove -f pve/vm-<VMID>-cloudinit
lvremove -f pve/vm-<VMID>-disk-0

# List all thin volumes
lvs -a | grep pve

# View active tasks
cat /var/log/pve/tasks/active

# Monitor NFS I/O
nfsiostat 1

# Check NFS mount status
mount | grep nfs
```

**Related:** TS-PVE-009 (NFS shutdown hang) - NFS storage hang during shutdown

## 9. Workaround (if any)
> If NFS is slow: Restore to local storage first (`--storage local-lvm`), then migrate disks to NFS after restore completes.
