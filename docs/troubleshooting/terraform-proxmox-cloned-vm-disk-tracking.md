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

## Key Takeaways

1. **Cloned VMs don't auto-track disks**: The bpg/proxmox provider doesn't populate disk state from cloned VMs
2. **Always declare boot disk**: When adding disks to cloned VMs, explicitly declare the boot disk (scsi0) with properties matching the source template
3. **Match template configuration**: The scsi0 disk block should mirror the golden image's disk configuration (size, datastore, format)
4. **discard=on**: Enables TRIM for SSD/thin-provisioned storage to reclaim space from deleted files

## Related Files

- Golden Image Template: `terraform/dev/proxmox/vms/golden-image/main.tf`
- FreeIPA VM: `terraform/dev/proxmox/vms/freeipa/main.tf`
- Golden Image Bootstrap: `proxmox/scripts/golden-vm-setup.sh`
