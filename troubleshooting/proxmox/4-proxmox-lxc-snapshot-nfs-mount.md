# TS-PVE-004 | 2026-03-08 | RESOLVED

## 1. Context
- System: Proxmox VE 8.x with NFS storage
- Environment: Dev/Prod Proxmox servers
- Related components: LXC containers, NFS storage (NAS), local-lvm, Terraform

## 2. Issue
- Symptom: When attempting to take a snapshot of an LXC container, Proxmox displays error
- Error:
```
The current guest configuration does not support taking new snapshots
```

**Example problematic configuration:**
```bash
root@pve-dev:~# pct config 2001
rootfs: local-lvm:vm-2001-disk-0,size=10G
mp0: nas-dev-data:2001/vm-2001-disk-0.raw,mp=/opt/ansible,size=5G
```

## 3. Analysis

**Why snapshots fail:**
LXC snapshots require **all storage volumes** to support snapshots. NFS storage does not support native snapshots.

When a container has:
- `rootfs` on `local-lvm` (supports snapshots)
- `mp0` on NFS storage like `nas-dev-data` (does NOT support snapshots)

The snapshot operation fails because not all volumes can be snapshotted.

**Storage Comparison:**

| Storage Type | Snapshots | Use Case |
|--------------|-----------|----------|
| local-lvm | Yes | OS disks, mount points needing snapshots |
| NFS (NAS) | No | Shared data, ISOs, backups, templates |
| ZFS | Yes | OS disks, mount points |
| Ceph | Yes | Clustered storage |

## 4. Root Cause
> LXC snapshots require all storage volumes to support snapshots. Container had mount point on NFS storage which does not support snapshots, causing entire snapshot operation to fail.

## 5. Solution
> Move mount point from NFS storage to local-lvm storage.

### Step 1: Move the volume

```bash
# Stop the container
pct stop <ctid>

# Move the mount point to local-lvm
pct move-volume <ctid> mp0 local-lvm

# Start the container
pct start <ctid>

# Verify the new configuration
pct config <ctid>
```

### Step 2: Clean up unused disk

After moving, the old NFS disk remains as `unused0`. Remove it:

```bash
pct set <ctid> --delete unused0
```

### Step 3: Verify snapshots work

```bash
pct snapshot <ctid> test-snapshot
pct listsnapshot <ctid>
pct delsnapshot <ctid> test-snapshot
```

### Batch Update (Multiple Containers)

For containers 2001-2006:

```bash
for ctid in 2001 2002 2003 2004 2005 2006; do
  echo "=== Processing CT $ctid ==="
  pct stop $ctid
  pct move-volume $ctid mp0 local-lvm
  pct start $ctid
  pct set $ctid --delete unused0
done
```

### Terraform Configuration Update

Update the mount point configuration in Terraform to match the new storage.

**Before (NFS - does not support snapshots):**
```hcl
variable "mount_points" {
  default = {
    mount_1 = {
      volume = "nas-dev-data"  # NFS storage
      size   = "5G"
      path   = "/opt/ansible"
    }
  }
}
```

**After (local-lvm - supports snapshots):**
```hcl
variable "mount_points" {
  default = {
    mount_1 = {
      volume = "local-lvm"  # LVM storage
      size   = "5G"
      path   = "/opt/ansible"
    }
  }
}
```

### Files updated:

**Dev environment:**
- `terraform/dev/proxmox/lxc/ansible/variables.tf`
- `terraform/dev/proxmox/lxc/vault_cluster/variables.tf`
- `terraform/dev/proxmox/lxc/nginx/variables.tf`
- `terraform/dev/proxmox/lxc/local_runner/variables.tf`

**Prod environment:**
- `terraform/prod/proxmox/lxc/ansible/variables.tf`
- `terraform/prod/proxmox/lxc/vault_cluster/variables.tf`
- `terraform/prod/proxmox/lxc/nginx/variables.tf`
- `terraform/prod/proxmox/lxc/local_runner/variables.tf`

### Sync Terraform State

After manual volume move, sync Terraform state with reality:

```bash
terraform apply -refresh-only
```

This updates the state file to match actual Proxmox configuration without making infrastructure changes.

**Note:** Running `terraform plan` directly would show "replace" for the container because Terraform cannot move volumes in-place. Always do manual move first, then refresh state.

## 6. Solution Risk
- Risk level: LOW
- Potential impact: Container downtime during volume move (stop/start required)

## 7. Impact After Fix
- Observed: Snapshots now work on all containers
- Mount points on local-lvm storage
- Terraform state synced with actual configuration

## 8. Notes

**Backups vs Snapshots:**

Even without snapshot support, **vzdump backups still work** with NFS mount points:

```
INFO: backup mode: snapshot
INFO: creating vzdump archive '/mnt/pve/nas-dev-data/dump/vzdump-lxc-2001-2026_03_08-18_39_39.tar.zst'
```

Vzdump creates a temporary LVM snapshot of the rootfs, backs up the container, then removes the snapshot. This works regardless of mount point storage type (mount points can be excluded from backup).

**Prevention:**

When creating new LXC containers that need snapshot capability:
1. Use `local-lvm` or ZFS for all mount points
2. Reserve NFS storage for:
   - ISO images
   - Container templates
   - Backup storage (vzdump destination)
   - Shared data that doesn't need snapshots

**Commands Reference:**
```bash
# Check container config
pct config <ctid>

# Stop container
pct stop <ctid>

# Move mount point to local-lvm
pct move-volume <ctid> mp0 local-lvm

# Start container
pct start <ctid>

# Delete unused disk
pct set <ctid> --delete unused0

# Take snapshot
pct snapshot <ctid> test-snapshot

# List snapshots
pct listsnapshot <ctid>

# Delete snapshot
pct delsnapshot <ctid> test-snapshot

# Sync Terraform state after manual changes
terraform apply -refresh-only
```

## 9. Workaround (if any)
> Use vzdump backups instead of snapshots for containers with NFS mount points. Backups work regardless of storage type.

## Related Files
- `terraform/dev/proxmox/lxc/*/variables.tf`
- `terraform/prod/proxmox/lxc/*/variables.tf`
