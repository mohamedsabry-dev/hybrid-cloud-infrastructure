# Case 10: VM Restore Hang — Concurrent NFS Operations

## Status: RESOLVED
## Date: 2026-03-26
## Duration: ~15 minutes
## Environment: Dev environment - Multiple VM restores from NFS backup storage

---

## Symptoms

- VM restore operations stuck at 100% for 10+ minutes
- Proxmox Web UI shows restore task "running" but no progress
- Multiple restore operations started simultaneously (6 VMs)
- User cancelled stuck tasks, leaving orphaned LVM volumes
- Subsequent restore attempts failed with LVM errors

**Error Message:**
```
Logical Volume "vm-1012-cloudinit" already exists in volume group "pve"
```

---

## Root Cause

**Too many concurrent restore operations overwhelmed NFS storage.**

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

---

## Resolution

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

**For multiple VMs (example with 4 stuck VMs):**
```bash
# VM 1012
lvremove -f pve/vm-1012-cloudinit
lvremove -f pve/vm-1012-disk-0

# VM 1022
lvremove -f pve/vm-1022-cloudinit
lvremove -f pve/vm-1022-disk-0

# VM 1032
lvremove -f pve/vm-1032-cloudinit
lvremove -f pve/vm-1032-disk-0

# VM 1042
lvremove -f pve/vm-1042-cloudinit
lvremove -f pve/vm-1042-disk-0
```

### Step 4: Retry Restore Sequentially

```bash
# Restore one VM at a time
qmrestore /mnt/pve/stor0/dump/vzdump-qemu-1012-*.vma.zst 1012

# Wait for completion, then next
qmrestore /mnt/pve/stor0/dump/vzdump-qemu-1022-*.vma.zst 1022
```

---

## Commands Reference

### LVM Cleanup
```bash
# List volumes for specific VM
lvs | grep vm-<VMID>

# Remove specific volume (force)
lvremove -f pve/vm-<VMID>-cloudinit
lvremove -f pve/vm-<VMID>-disk-0

# List all thin volumes
lvs -a | grep pve
```

### Task Management
```bash
# View active tasks
cat /var/log/pve/tasks/active

# Check task log
cat /var/log/pve/tasks/<task-id>
```

### NFS Monitoring
```bash
# Check NFS mount status
mount | grep nfs

# Monitor NFS I/O
nfsiostat 1

# Check NFS server response
showmount -e <nfs-server>
```

---

## Prevention

### Limit Concurrent Operations

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

---

## Related Issues

- Case 9: `9-nfs-shutdown-hang-stor0-hotswap.md` - NFS storage hang during shutdown

---

## Status

✅ **Resolved** - VMs restored successfully after sequential restore approach
