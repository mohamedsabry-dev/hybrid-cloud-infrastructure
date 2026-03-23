# Troubleshooting: LVM Thin Pool Resize and Overcommit Warning

**Date**: 2026-03-23
**Affected**: pve-dev (also applicable to pve-prod)
**Resolution**: Delete and recreate thin pool at smaller size + enable auto-extend

---

## Symptoms

### Warning 1: Snapshot Creation Warnings
When creating VM snapshots, LVM displays warnings:

```
Logical volume "snap_vm-2006-disk-0_Before_Vault" created.
WARNING: You have not turned on protection against thin pools running out of space.
WARNING: Set activation/thin_pool_autoextend_threshold below 100 to trigger automatic extension of thin pools before they get full.
Logical volume "snap_vm-2006-disk-1_Before_Vault" created.
WARNING: Sum of all thin volume sizes (<350.03 GiB) exceeds the size of thin pool pve/data and the amount of free space in volume group (16.00 GiB).
```

### Warning 2: Proxmox UI Shows 97% Assigned
In Proxmox UI → Disks → LVM:
- **Assigned to LVs**: 97% (shown in red)
- **Free**: 17.18 GB

This looks alarming but is misleading (see Root Cause Analysis).

---

## Root Cause Analysis

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

---

## Investigation

### Step 1: Check Thin Pool Status
```bash
root@pve-dev:~# lvs -o lv_name,lv_size,data_percent pve/data
  LV   LSize    Data%
  data <348.82g 12.42
```

Result: Only 12.42% actual usage - plenty of space.

### Step 2: Calculate Terraform Disk Allocation

Analyzed all Terraform configurations in `/terraform/dev/proxmox/`:

**On local-lvm:**
| Resource | Size | Count | Total |
|----------|------|-------|-------|
| golden-image | 20 GB | 1 | 20 GB |
| freeipa (OS) | 25 GB | 1 | 25 GB |
| k8s_masters | 25 GB | 3 | 75 GB |
| k8s_workers (OS) | 25 GB | 3 | 75 GB |
| vault_cluster | 15 GB | 3 | 45 GB |
| ansible | 15 GB | 1 | 15 GB |
| local_runner | 20 GB | 1 | 20 GB |
| nginx | 15 GB | 1 | 15 GB |
| golden-template | 10 GB | 1 | 10 GB |
| **Subtotal** | | | **300 GB** |

**On NAS (nas-dev-data):**
| Resource | Size | Count | Total |
|----------|------|-------|-------|
| freeipa (data) | 25 GB | 1 | 25 GB |
| k8s_workers (data) | 80 GB | 3 | 240 GB |
| **Subtotal** | | | **265 GB** |

Extra ~50 GB allocation from snapshots and templates.

### Step 3: Attempt to Shrink Thin Pool

**Tested:**
```bash
root@pve-dev:~# lvreduce -t -L 320G /dev/pve/data
  TEST MODE: Metadata will NOT be updated and volumes will not be (de)activated.
  Thin pool volumes pve/data_tdata cannot be reduced in size yet.
```

**Result:** LVM thin pools cannot be shrunk directly - this is a known limitation.

---

## Solution

### Option A: Enable Auto-Extend Only (Quick Fix)

If you don't want to resize, just enable auto-extend:

```bash
# Edit /etc/lvm/lvm.conf
nano /etc/lvm/lvm.conf

# Find and set:
thin_pool_autoextend_threshold = 80
thin_pool_autoextend_percent = 10

# Restart monitor
systemctl restart lvm2-monitor
```

### Option B: Delete and Recreate Thin Pool (Full Solution)
## The selected one

Based on Proxmox forum solution: https://forum.proxmox.com/threads/resizing-pve-data.30506/

This reclaims space at the VG level for better auto-extend headroom.

#### Prerequisites
- [ ] Backup task updated to include golden images and templates
- [ ] All backups stored on NAS (not local storage)
- [ ] Sufficient NAS space for full backup
- [ ] Verified all disks and mount points included (see checklist below)

#### Backup Verification Checklist

**List all VMs and LXCs:**
```bash
# VMs
qm list

# LXCs
pct list
```

**Verify VM disk configuration:**
```bash
# For each VM, check all disks are on backup-enabled storage
qm config <VMID> | grep -E "^(scsi|virtio|ide|sata)[0-9]"
```

**Verify LXC rootfs and mount points:**
```bash
# For each LXC, check rootfs and mount points
pct config <CTID> | grep -E "^(rootfs|mp[0-9])"
```

**Check mount point backup flag:**
```bash
# Mount points with backup=0 are EXCLUDED from backup!
pct config <CTID> | grep "backup=0"
```

**Expected resources to backup (Dev environment):**

| Type | ID | Name | Disks/Mounts |
|------|-----|------|--------------|
| VM | 9000 | golden-image | scsi0 (20G) |
| VM | 1001 | freeipa | scsi0 (25G), scsi1 (25G) |
| VM | 1010 | k8s-master1 | scsi0 (25G) |
| VM | 1011 | k8s-master2 | scsi0 (25G) |
| VM | 1012 | k8s-master3 | scsi0 (25G) |
| VM | 1020 | k8s-worker1 | scsi0 (25G), scsi1 (80G) |
| VM | 1021 | k8s-worker2 | scsi0 (25G), scsi1 (80G) |
| VM | 1022 | k8s-worker3 | scsi0 (25G), scsi1 (80G) |
| LXC | 9010 | golden-template | rootfs (10G) |
| LXC | 2001 | ansible | rootfs (10G), mp0 (5G) |
| LXC | 2002 | local-runner | rootfs (15G), mp0 (5G) |
| LXC | 2003 | nginx | rootfs (10G), mp0 (5G) |
| LXC | 2004 | vault1 | rootfs (10G), mp0 (5G) |
| LXC | 2005 | vault2 | rootfs (10G), mp0 (5G) |
| LXC | 2006 | vault3 | rootfs (10G), mp0 (5G) |

**Verify backup job includes all:**
```bash
# Check backup job configuration
cat /etc/pve/jobs.cfg
# Or via UI: Datacenter → Backup → Edit job → check "all" or specific VMIDs
```

**Check NAS has enough space:**
```bash
# Estimate: actual usage × 1.5 (compression overhead)
df -h /mnt/pve/nas-backups
```

#### Procedure

**1. Update Backup Task**

Ensure backup job includes:
- All VMs (including golden-image VM)
- All LXCs (including golden-template)
- Templates

**2. Shutdown Everything**
```bash
# Stop all VMs
qm list | awk 'NR>1 {print $1}' | xargs -I {} qm stop {}

# Stop all LXCs
pct list | awk 'NR>1 {print $1}' | xargs -I {} pct stop {}
```

**3. Run Full Backup**
```bash
# Via UI: Datacenter → Backup → Run Now
# Or via CLI:
vzdump --all --storage nas-backups --mode stop --compress zstd
```

**4. Verify Backups on NAS**
```bash
# Check backup storage
ls -la /mnt/pve/nas-backups/dump/
```

**5. Delete Thin Pool**
```bash
# Remove the thin pool
lvremove /dev/pve/data
```

**6. Recreate at Smaller Size**
```bash
# Create new thin pool at 250 GB (5x current usage)
lvcreate -L 250G -T pve/data
```

**7. Verify New Allocation**
```bash
# Check VG free space (should show ~140 GB free now)
vgs pve

# Check thin pool
lvs pve/data
```

**8. Restore from Backup**
```bash
# Via UI: Select backup → Restore
# Or via CLI:
qmrestore /mnt/pve/nas-backups/dump/vzdump-qemu-XXX.vma.zst VMID --storage local-lvm
pct restore CTID /mnt/pve/nas-backups/dump/vzdump-lxc-XXX.tar.zst --storage local-lvm
```

**9. Enable Auto-Extend**
```bash
# Edit /etc/lvm/lvm.conf
sed -i 's/thin_pool_autoextend_threshold = 100/thin_pool_autoextend_threshold = 80/' /etc/lvm/lvm.conf
sed -i 's/# thin_pool_autoextend_percent = 20/thin_pool_autoextend_percent = 10/' /etc/lvm/lvm.conf

# Restart LVM monitor
systemctl restart lvm2-monitor

# Verify settings
grep -E "thin_pool_autoextend" /etc/lvm/lvm.conf
```

**10. Start VMs/LXCs**
```bash
# Start critical services first
qm start <freeipa-vmid>
sleep 30
# Then start others
```

---

## Final State

After resize:

| Metric | Before | After |
|--------|--------|-------|
| Thin Pool Size | 374 GB | 250 GB |
| VG Free Space | 17 GB | ~140 GB |
| Auto-extend | Disabled | 80% threshold, 10% growth |
| Actual Usage | 12% (~46 GB) | ~18% (~46 GB) |

The 140 GB VG free space provides ample room for auto-extend operations.

---

## Auto-Extend Behavior

With settings:
- `thin_pool_autoextend_threshold = 80`
- `thin_pool_autoextend_percent = 10`

| Event | Action |
|-------|--------|
| Usage hits 80% (200 GB) | Auto-extend by 10% (25 GB) |
| New pool size | 275 GB |
| Can repeat | Until VG free space exhausted |

---

## Monitoring

### Check Thin Pool Usage
```bash
lvs -o lv_name,lv_size,data_percent pve/data
```

### Check VG Free Space
```bash
vgs pve -o vg_name,vg_size,vg_free
```

### Proxmox UI
- Datacenter → Storage → local-lvm → shows actual usage %
- Node → Disks → LVM-Thin → detailed view

---

## Prevention

1. **Size thin pools appropriately** - 2-5x expected actual usage
2. **Always enable auto-extend** on new Proxmox installations
3. **Use NAS for data disks** - reduces local-lvm pressure
4. **Clean up old snapshots** regularly
5. **Monitor actual usage**, not allocated space

---

## Related

- [43: Switch Port 4 Link Flapping](../network/43-switch-port4-link-flapping-loose-connection.md) - discovered during same session
- [48: ER605 Port 4 Gigabit Negotiation](../network/48-er605-port4-gigabit-negotiation.md) - related hardware issue
- Proxmox Forum: https://forum.proxmox.com/threads/resizing-pve-data.30506/

---

## Status

PENDING - Backup and resize procedure to be executed
