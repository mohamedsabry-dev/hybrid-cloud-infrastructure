# TS-PVE-008 | 2026-03-23 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Proxmox VE LVM thin provisioning
Sub-techs: pve/data thin pool, local-lvm storage, vzdump backups
Environment: pve-dev (also applicable to pve-prod)
Re-opened: No

_____________________________________________________________________

[Issue Description]
LVM warnings during snapshot creation, Proxmox UI shows 97% assigned (red warning).

```
Logical volume "snap_vm-2006-disk-0_Before_Vault" created.
WARNING: You have not turned on protection against thin pools running out of space.
WARNING: Set activation/thin_pool_autoextend_threshold below 100 to trigger automatic extension of thin pools before they get full.
Logical volume "snap_vm-2006-disk-1_Before_Vault" created.
WARNING: Sum of all thin volume sizes (<350.03 GiB) exceeds the size of thin pool pve/data and the amount of free space in volume group (16.00 GiB).
```

_____________________________________________________________________

[Analysis]
# Step 1: Understand the two views

| View | What It Shows | Value |
|------|---------------|-------|
| LVM (VG level) | All logical volumes including thin pool itself | 97% assigned |
| LVM-Thin (pool level) | Actual data written inside thin pool | 12% used |

The 97% "assigned" includes:
```
Volume Group (pve):     511 GB total
├── pve/root:           ~96 GB (Proxmox OS)
├── pve/swap:           ~8 GB
├── pve/data (thin):    374 GB ← thin pool allocation
└── Free in VG:         17 GB
```

# Step 2: Thin provisioning math

| Term | Meaning | Our Value |
|------|---------|-----------|
| Allocated | Sum of all thin volume sizes | ~350 GB |
| Pool Size | Actual thin pool capacity | 374 GB |
| Actual Usage | Data really written to disk | 46 GB (12%) |

Thin provisioning allows overcommit -- allocating more than physical capacity. This is normal.

# Step 3: Check actual usage
```bash
root@pve-dev:~# lvs -o lv_name,lv_size,data_percent pve/data
  LV   LSize    Data%
  data <348.82g 12.42
```
Only 12.42% actual usage -- plenty of space. The warnings are about allocation, not actual usage.

# Step 4: Assess real risk
Unlike VMware (which pauses VMs gracefully), LVM thin pools can cause I/O errors, data corruption, and VM freezes if actual usage fills the pool with no auto-extend configured.

_____________________________________________________________________

[Final Root Cause]
No auto-extend configured for thin pool. Warnings appear because sum of allocated thin volumes exceeds pool size + VG free space. While actual usage (12%) is safe, running out of space with no auto-extend would cause I/O errors.

_____________________________________________________________________

[Final Solution]
I chose Option B: Delete and recreate thin pool at smaller size, then enable auto-extend. This reclaims space at VG level for better auto-extend headroom.

Procedure:

1. Shutdown everything (graceful)
```bash
qm list | awk 'NR>1 {print $1}' | xargs -I {} qm shutdown {}
pct list | awk 'NR>1 {print $1}' | xargs -I {} pct shutdown {}
watch -n 5 'qm list; echo "---"; pct list'
```

2. Run full backup
```bash
vzdump --all --storage nas-dev-data --mode stop --compress zstd
```

3. Save current LVM config
```bash
mkdir -p /root/lvm-backup-$(date +%Y%m%d)
lvs -a -o +devices > /root/lvm-backup-$(date +%Y%m%d)/lvs-full.txt
vgs -o +devices > /root/lvm-backup-$(date +%Y%m%d)/vgs-full.txt
cat /etc/lvm/lvm.conf > /root/lvm-backup-$(date +%Y%m%d)/lvm.conf.bak
```

4. Delete thin pool
```bash
lvremove pve/data
```

5. Remove orphan VM/LXC configs
```bash
rm /etc/pve/qemu-server/*.conf
rm /etc/pve/lxc/*.conf
```

6. Recreate at smaller size
```bash
lvcreate -L 250G -T /dev/pve/data
```

7. Verify new allocation
```bash
vgs pve  # Should show ~140 GB free now
lvs /dev/pve/data
```

8. Restore from backup
```bash
qmrestore /mnt/pve/nas-dev-data/dump/vzdump-qemu-XXX.vma.zst VMID --storage local-lvm
pct restore CTID /mnt/pve/nas-dev-data/dump/vzdump-lxc-XXX.tar.zst --storage local-lvm
```

9. Enable auto-extend
```bash
nano /etc/lvm/lvm.conf
# Set:
#   thin_pool_autoextend_threshold = 80
#   thin_pool_autoextend_percent = 10

systemctl restart lvm2-monitor
```

10. Start VMs/LXCs

After resize, warnings still appear during snapshot operations -- this is normal. The warning is about allocation, not actual usage.

| Metric | Before | After |
|--------|--------|-------|
| Thin Pool Size | 374 GB | 250 GB |
| VG Free Space | 17 GB | ~140 GB |
| Auto-extend | Disabled | 80% threshold, 10% growth |
| Actual Usage | 12% (~46 GB) | ~18% (~46 GB) |

Monitoring commands:
```bash
lvs -o lv_name,lv_size,data_percent pve/data
vgs pve -o vg_name,vg_size,vg_free
```

Same procedure applies to pve-prod (swap `nas-dev-data` for `nas-prod-data`).

Verified: Yes -- thin pool resized, auto-extend enabled, all VMs/LXCs restored.

_____________________________________________________________________

[Risk Level] HIGH -- all VMs/LXCs must be stopped and restored from backup. Snapshots are NOT included in vzdump and will be lost.

_____________________________________________________________________

[References]
- Proxmox Forum: https://forum.proxmox.com/threads/resizing-pve-data.30506/
