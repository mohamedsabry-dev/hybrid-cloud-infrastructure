# TS-PVE-008 | 2026-03-23 | RESOLVED

## 1. Context
- System: Proxmox VE LVM thin provisioning
- Environment: pve-dev (also applicable to pve-prod)
- Related components: pve/data thin pool, local-lvm storage, vzdump backups

## 2. Issue
- Symptom: LVM warnings during snapshot creation, Proxmox UI shows 97% assigned (red warning)
- Error:
```
Logical volume "snap_vm-2006-disk-0_Before_Vault" created.
WARNING: You have not turned on protection against thin pools running out of space.
WARNING: Set activation/thin_pool_autoextend_threshold below 100 to trigger automatic extension of thin pools before they get full.
Logical volume "snap_vm-2006-disk-1_Before_Vault" created.
WARNING: Sum of all thin volume sizes (<350.03 GiB) exceeds the size of thin pool pve/data and the amount of free space in volume group (16.00 GiB).
```

## 3. Analysis

### Understanding the Two Views

| View | What It Shows | Value |
|------|---------------|-------|
| **LVM (VG level)** | All logical volumes including thin pool itself | 97% assigned |
| **LVM-Thin (pool level)** | Actual data written inside thin pool | 12% used |

The 97% "assigned" includes:
```
Volume Group (pve):     511 GB total
├── pve/root:           ~96 GB (Proxmox OS)
├── pve/swap:           ~8 GB
├── pve/data (thin):    374 GB ← thin pool allocation
└── Free in VG:         17 GB
```

### Thin Provisioning Explained

| Term | Meaning | Our Value |
|------|---------|-----------|
| **Allocated** | Sum of all thin volume sizes | ~350 GB |
| **Pool Size** | Actual thin pool capacity | 374 GB |
| **Actual Usage** | Data really written to disk | 46 GB (12%) |

Thin provisioning allows overcommit - allocating more than physical capacity. This is normal and expected.

### The Real Risk

Unlike VMware (which pauses VMs gracefully), LVM thin pools can cause:
- I/O errors
- Data corruption
- VM freezes

...if actual usage fills the pool completely with no auto-extend configured.

### Investigation

```bash
root@pve-dev:~# lvs -o lv_name,lv_size,data_percent pve/data
  LV   LSize    Data%
  data <348.82g 12.42
```

Result: Only 12.42% actual usage - plenty of space. The warnings are about allocation, not actual usage.

## 4. Root Cause
> No auto-extend configured for thin pool. Warnings appear because sum of allocated thin volumes exceeds pool size + VG free space. While actual usage (12%) is safe, running out of space with no auto-extend would cause I/O errors.

## 5. Solution
> Resize thin pool smaller and enable auto-extend. This provides headroom in VG for auto-extend operations.

### Option A: Enable Auto-Extend Only (Quick Fix)

```bash
# Edit /etc/lvm/lvm.conf
nano /etc/lvm/lvm.conf

# Find and set:
thin_pool_autoextend_threshold = 80
thin_pool_autoextend_percent = 10

# Restart monitor
systemctl restart lvm2-monitor
```

### Option B: Delete and Recreate Thin Pool (Full Solution - Selected)

Based on Proxmox forum solution. This reclaims space at VG level for better auto-extend headroom.

#### Prerequisites
- [ ] Backup task updated to include golden images and templates
- [ ] All backups stored on NAS (not local storage)
- [ ] Sufficient NAS space for full backup
- [ ] Verified all disks and mount points included

#### Procedure

**1. Shutdown Everything (Graceful)**
```bash
# Graceful shutdown all VMs
qm list | awk 'NR>1 {print $1}' | xargs -I {} qm shutdown {}

# Graceful shutdown all LXCs
pct list | awk 'NR>1 {print $1}' | xargs -I {} pct shutdown {}

# Wait for all to stop
watch -n 5 'qm list; echo "---"; pct list'
```

**2. Run Full Backup**
```bash
vzdump --all --storage nas-dev-data --mode stop --compress zstd
```

**3. Save Current LVM Config**
```bash
mkdir -p /root/lvm-backup-$(date +%Y%m%d)
lvs -a -o +devices > /root/lvm-backup-$(date +%Y%m%d)/lvs-full.txt
vgs -o +devices > /root/lvm-backup-$(date +%Y%m%d)/vgs-full.txt
cat /etc/lvm/lvm.conf > /root/lvm-backup-$(date +%Y%m%d)/lvm.conf.bak
```

**4. Delete Thin Pool**
```bash
lvremove pve/data
```

**5. Remove Orphan VM/LXC Configs**
```bash
# Remove VM configs
rm /etc/pve/qemu-server/*.conf

# Remove LXC configs
rm /etc/pve/lxc/*.conf
```

**6. Recreate at Smaller Size**
```bash
# Create new thin pool at 250 GB (5x current usage)
lvcreate -L 250G -T /dev/pve/data
```

**7. Verify New Allocation**
```bash
vgs pve  # Should show ~140 GB free now
lvs /dev/pve/data
```

**8. Restore from Backup**
```bash
# Via UI or CLI
qmrestore /mnt/pve/nas-dev-data/dump/vzdump-qemu-XXX.vma.zst VMID --storage local-lvm
pct restore CTID /mnt/pve/nas-dev-data/dump/vzdump-lxc-XXX.tar.zst --storage local-lvm
```

**9. Enable Auto-Extend**
```bash
nano /etc/lvm/lvm.conf
# Set:
#   thin_pool_autoextend_threshold = 80
#   thin_pool_autoextend_percent = 10

systemctl restart lvm2-monitor
```

**10. Start VMs/LXCs**

## 6. Solution Risk
- Risk level: HIGH
- Potential impact: All VMs/LXCs must be stopped and restored from backup. Snapshots are NOT included in vzdump - they will be lost.

## 7. Impact After Fix
- Observed: Thin pool resized from 374 GB to 250 GB
- VG free space increased from 17 GB to ~140 GB
- Auto-extend enabled at 80% threshold
- Warnings still appear (normal for thin provisioning) but system is protected

| Metric | Before | After |
|--------|--------|-------|
| Thin Pool Size | 374 GB | 250 GB |
| VG Free Space | 17 GB | ~140 GB |
| Auto-extend | Disabled | 80% threshold, 10% growth |
| Actual Usage | 12% (~46 GB) | ~18% (~46 GB) |

## 8. Notes

### Warning After Fix is Normal

After resize, you will **still see warnings** during snapshot operations:

```
WARNING: Sum of all thin volume sizes (423.49 GiB) exceeds the size of thin pool pve/data
  and the amount of free space in volume group (<121.69 GiB).
TASK OK
```

**This is normal.** The warning is about **allocation** (423 GB), not **actual usage** (15%).

### Monitoring Commands

```bash
# Check thin pool actual usage
lvs -o lv_name,lv_size,data_percent pve/data

# Check VG free space
vgs pve -o vg_name,vg_size,vg_free
```

### Auto-Extend Behavior

With settings `threshold=80`, `percent=10`:

| Event | Action |
|-------|--------|
| Usage hits 80% (200 GB) | Auto-extend by 10% (25 GB) |
| New pool size | 275 GB |
| Can repeat | Until VG free space exhausted |

### Prevention

1. **Size thin pools appropriately** - 2-5x expected actual usage
2. **Always enable auto-extend** on new Proxmox installations
3. **Use NAS for data disks** - reduces local-lvm pressure
4. **Clean up old snapshots** regularly
5. **Monitor actual usage**, not allocated space

### Prod Environment

Same procedure applies to pve-prod:
- SSH target: `pve-dev` → `pve-prod`
- Backup storage: `nas-dev-data` → `nas-prod-data`
- LVM paths are identical (Proxmox defaults)

## 9. Workaround (if any)
> If you don't want to delete/recreate: Just enable auto-extend (Option A). Warnings will continue but system is protected from running out of space.

## References
- Proxmox Forum: https://forum.proxmox.com/threads/resizing-pve-data.30506/
