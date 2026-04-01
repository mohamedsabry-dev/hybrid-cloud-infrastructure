# Terraform Proxmox Provider: Cloned VM Disk State Tracking Issue

## Overview

When using the `bpg/proxmox` Terraform provider to clone a VM and later add a data disk, Terraform may exhibit unexpected behavior due to how it tracks disk state for cloned VMs.

## Environment

- Terraform: 1.14.3
- Provider: bpg/proxmox
- VM: FreeIPA (ID 1001) cloned from golden-image (ID 9000)

## The Issue

### Initial State After Clone

When a VM is cloned, the provider **does not track the cloned disk** in Terraform state. The disk array remains empty:

```json
// terraform.tfstate after clone (BEFORE fix)
{
  "disk": [],
  ...
}
```

Despite `scsi0` existing in Proxmox (inherited from clone), Terraform is unaware of it.

### Problem: Adding Only Data Disk

When we tried to add only the new data disk:

```hcl
# What we tried (WRONG approach)
disk {
  datastore_id = "nas-dev-data"
  interface    = "scsi1"
  size         = 25
  file_format  = "raw"
}
```

### Terraform Plan Output (Unexpected Behavior)

```
~ disk {
    ~ datastore_id = "local-lvm" -> "nas-dev-data"
    ~ interface    = "scsi0" -> "scsi1"
    ~ size         = 20 -> 25
}
- disk {
    - datastore_id = "nas-dev-data" -> null
    - interface    = "scsi1" -> null
    ...
}
```

**What Terraform tried to do:**
1. Transform scsi0 properties to match scsi1 configuration
2. Delete what it thought was scsi1 (didn't exist yet)

This happened because Terraform had no record of scsi0, so it misinterpreted the disk configuration entirely.

## The Solution

### Explicitly Declare Both Disks

Declare the boot disk (scsi0) matching the golden image template configuration, plus the new data disk:

```hcl
# Boot disk - must match golden image template
disk {
  datastore_id = var.datastore_id  # "local-lvm"
  interface    = "scsi0"
  size         = 20
  ssd          = true
  discard      = "on"
  file_format  = "raw"
}

# Data disk - new addition
disk {
  datastore_id = "nas-dev-data"
  interface    = "scsi1"
  size         = 25
  ssd          = true
  discard      = "on"
  file_format  = "raw"
}
```

### Clean Terraform Plan After Fix

```
~ disk {
    ~ discard = "ignore" -> "on"
    ~ ssd     = false -> true
}
~ disk {
    ~ size = 20 -> 25
}
```

Now Terraform correctly:
1. Recognizes scsi0 and adjusts properties (discard, ssd)
2. Manages scsi1 as the data disk

## Validation

### New tfstate (AFTER fix)

```json
// terraform.tfstate - now correctly tracking both disks
{
  "disk": [
    {
      "datastore_id": "local-lvm",
      "discard": "on",
      "interface": "scsi0",
      "path_in_datastore": "vm-1001-disk-0",
      "size": 20,
      "ssd": true
    },
    {
      "datastore_id": "nas-dev-data",
      "discard": "ignore",
      "interface": "scsi1",
      "path_in_datastore": "1001/vm-1001-disk-0.raw",
      "size": 25,
      "ssd": false
    }
  ]
}
```

### Proxmox Verification

```
Hard Disk (scsi0): local-lvm:vm-1001-disk-0,discard=on,size=20G,ssd=1
Hard Disk (scsi1): nas-dev-data:1001/vm-1001-disk-0.raw,size=25G
```

### VM Verification

```bash
lsblk
# NAME   SIZE
# sda    20G   (boot disk)
# sdb    25G   (data disk)
```

## Hot Resize: Expanding Disk While VM Running

Terraform/Proxmox supports **hot-resizing** disks without stopping the VM. The Linux kernel automatically detects the capacity change.

### Test: Resize scsi0 from 20GB to 25GB via GitHub Actions Workflow

**Before resize (VM running):**
```bash
[root@freeipa ~]# lsblk
NAME          MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda             8:0    0   20G  0 disk
├─sda1          8:1    0    1M  0 part
├─sda2          8:2    0    1G  0 part /boot
└─sda3          8:3    0   19G  0 part
  ├─rl-root   253:0    0   17G  0 lvm  /
  └─rl-swap   253:1    0    2G  0 lvm  [SWAP]
sdb             8:16   0   25G  0 disk
```

**Kernel detects capacity change automatically:**
```
[ 547.891964] sd 0:0:0:0: Capacity data has changed
[ 547.892203] sd 0:0:0:0: [sda] 52428800 512-byte logical blocks: (26.8 GB/25.0 GiB)
[ 547.894498] sda: detected capacity change from 41943040 to 52428800
```

**After resize (no reboot needed):**
```bash
[root@freeipa ~]# lsblk
NAME          MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda             8:0    0   25G  0 disk    # <-- Now 25GB
├─sda1          8:1    0    1M  0 part
├─sda2          8:2    0    1G  0 part /boot
└─sda3          8:3    0   19G  0 part    # <-- Partition still 19G
  ├─rl-root   253:0    0   17G  0 lvm  /
  └─rl-swap   253:1    0    2G  0 lvm  [SWAP]
sdb             8:16   0   25G  0 disk
```

### Next Steps to Use the New Space

The disk expanded but the partition/LVM needs manual expansion:

```bash
# 1. Grow the partition to use new space
growpart /dev/sda 3

# 2. Resize the physical volume
pvresize /dev/sda3

# 3. Extend the logical volume
lvextend -l +100%FREE /dev/rl/root

# 4. Grow the filesystem
xfs_growfs /
```

### Key Finding

- **Hot resize works**: Proxmox/Terraform can expand disks while VM is running
- **Kernel auto-detects**: Linux kernel sees capacity change immediately via SCSI hotplug
- **No VM downtime**: Resize happens live, workflow completes without stopping VM
- **Manual partition resize**: Filesystem expansion still requires manual commands inside VM

## Disk Naming Race Condition After Reboot

### The Problem

After VM reboot, disk device names (`sda`, `sdb`) may swap:

**Before reboot:**
```
sda   25G  (boot disk - scsi0)
├─sda1/2/3 partitions
sdb   25G  (data disk - scsi1)
```

**After reboot:**
```
sda   25G  (data disk - no partitions!)
sdb   25G  (boot disk - has all partitions!)
├─sdb1      1M  part
├─sdb2      1G  part /boot
└─sdb3     19G  part
  ├─rl-root 17G lvm  /
  └─rl-swap  2G lvm  [SWAP]
```

### Why This Happens

- Linux does **NOT** guarantee `sda` = `scsi0`
- Device names are assigned based on **probe order**, not SCSI interface ID
- After reboot, whichever disk is detected first becomes `sda`
- This is standard Linux behavior, not a Terraform/Proxmox bug

### Why the System Still Boots

- **GRUB**: Uses UUID to locate boot partition
- **LVM**: Uses UUID for physical volume identification
- **/etc/fstab**: Rocky Linux uses LVM device names (`/dev/mapper/rl-root`)
- The boot process doesn't rely on `/dev/sda` being the boot disk

### Best Practices

**Never rely on device names (`sda`, `sdb`) for:**
- Scripts that format/mount disks
- Backup operations
- Ansible playbooks

**Always use persistent identifiers:**
```bash
# By UUID
/dev/disk/by-uuid/xxxx-xxxx

# By LVM name
/dev/mapper/rl-root

# By SCSI path (consistent with Proxmox interface)
/dev/disk/by-path/pci-0000:00:1f.2-scsi-0:0:0:0  # scsi0
/dev/disk/by-path/pci-0000:00:1f.2-scsi-0:0:1:0  # scsi1

# By Proxmox disk ID
/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0
/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1
```

### Verify Disk Identity

```bash
# Check which physical disk is which
ls -la /dev/disk/by-path/
ls -la /dev/disk/by-id/ | grep scsi

# Show SCSI host:channel:target:lun
lsblk -o NAME,SIZE,HCTL,SERIAL
```

## Formatting and Mounting Data Disk with UUID

### Step-by-Step Procedure

After the disk naming swap, follow these steps to properly format and mount the data disk using UUID (which persists across reboots regardless of device name).

**1. Identify the data disk (scsi1):**
```bash
ls -la /dev/disk/by-id/ | grep scsi
```

Example output:
```
scsi-0QEMU_QEMU_HARDDISK_drive-scsi0 -> ../../sdb  (boot disk)
scsi-0QEMU_QEMU_HARDDISK_drive-scsi1 -> ../../sda  (data disk)
```

In this case, `sda` is the data disk (scsi1).

**2. Create partition on the data disk:**
```bash
fdisk /dev/sda
```

Interactive steps:
- `n` - new partition
- `p` - primary
- `1` - partition number
- `Enter` - default first sector
- `Enter` - default last sector (use all space)
- `w` - write and exit

**3. Verify partition created:**
```bash
lsblk
```

Expected output:
```
sda           8:0    0   25G  0 disk
└─sda1        8:1    0   25G  0 part
sdb           8:16   0   25G  0 disk
├─sdb1        8:17   0    1M  0 part
├─sdb2        8:18   0    1G  0 part /boot
└─sdb3        8:19   0   19G  0 part
  ├─rl-root 253:0    0   17G  0 lvm  /
  └─rl-swap 253:1    0    2G  0 lvm  [SWAP]
```

**4. Format as XFS:**
```bash
mkfs.xfs /dev/sda1
```

**5. Create mount point:**
```bash
mkdir -p /data
```

**6. Add to fstab using UUID (critical for persistence):**
```bash
echo "UUID=$(blkid -s UUID -o value /dev/sda1) /data xfs defaults 0 0" >> /etc/fstab
```

**7. Reload systemd and mount:**
```bash
systemctl daemon-reload
mount /data
```

**8. Verify:**
```bash
df -h /data
tail -1 /etc/fstab
```

Expected output:
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1        25G  522M   25G   3% /data

UUID=316ecfbc-1fb3-46b3-8c0c-405b1213cf97 /data xfs defaults 0 0
```

### Why UUID Matters

After reboot, the disk might become `sdb1` instead of `sda1`, but the UUID stays the same:
- **Without UUID**: `/dev/sda1` in fstab → mount fails if disk swaps to `sdb1`
- **With UUID**: `UUID=316ecfbc-...` in fstab → mounts correctly regardless of device name

### Quick One-Liner (after fdisk)

```bash
mkfs.xfs /dev/sda1 && \
mkdir -p /data && \
echo "UUID=$(blkid -s UUID -o value /dev/sda1) /data xfs defaults 0 0" >> /etc/fstab && \
systemctl daemon-reload && \
mount /data && \
df -h /data
```

## Key Takeaways

1. **Cloned VMs don't auto-track disks**: The bpg/proxmox provider doesn't populate disk state from cloned VMs
2. **Always declare boot disk**: When adding disks to cloned VMs, explicitly declare the boot disk (scsi0) with properties matching the source template
3. **Match template configuration**: The scsi0 disk block should mirror the golden image's disk configuration (size, datastore, format)
4. **discard=on**: Enables TRIM for SSD/thin-provisioned storage to reclaim space from deleted files
5. **Hot resize supported**: Disks can be expanded via Terraform while VM is running - kernel detects change automatically

## Related Files

- Golden Image Template: `terraform/dev/proxmox/vms/golden-image/main.tf`
- FreeIPA VM: `terraform/dev/proxmox/vms/freeipa/main.tf`
- Golden Image Bootstrap: `proxmox/golden_templates/golden-vm-setup.sh`
