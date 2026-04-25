# TS-PVE-004 | 2026-03-08 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Proxmox VE / LXC / Storage
Sub-techs: LXC snapshots, NFS storage, local-lvm, mount points,
           pct move-volume, Terraform state refresh
Environment: DEV & PROD Proxmox servers | NAS NFS storage
Re-opened: No

_____________________________________________________________________

[Issue Description]
Attempting to snapshot an LXC container failed:

```
The current guest configuration does not support taking new snapshots
```

Container config showed mount point on NFS:
```bash
root@pve-dev:~# pct config 2001
rootfs: local-lvm:vm-2001-disk-0,size=10G
mp0: nas-dev-data:2001/vm-2001-disk-0.raw,mp=/opt/ansible,size=5G
```

_____________________________________________________________________

[Analysis]

LXC snapshots require ALL storage volumes to support snapshots. NFS doesn't
support native snapshots.

Container had rootfs on `local-lvm` (supports snapshots) and mp0 on NFS
`nas-dev-data` (doesn't support snapshots). Mixed storage = snapshot fails.

Note: vzdump backups still work with NFS mount points — vzdump creates a
temporary LVM snapshot of rootfs and can back up mount point data separately.

_____________________________________________________________________

[Final Root Cause]
LXC snapshots require all storage volumes to support snapshots. Container had
mount point on NFS storage which doesn't support snapshots, causing the entire
snapshot operation to fail.

_____________________________________________________________________

[Final Solution]

Move mount points from NFS to local-lvm:

```bash
# Single container
pct stop <ctid>
pct move-volume <ctid> mp0 local-lvm
pct start <ctid>
pct set <ctid> --delete unused0    # remove leftover NFS disk

# Batch update for containers 2001-2006
for ctid in 2001 2002 2003 2004 2005 2006; do
  echo "=== Processing CT $ctid ==="
  pct stop $ctid
  pct move-volume $ctid mp0 local-lvm
  pct start $ctid
  pct set $ctid --delete unused0
done
```

Verify snapshots work:
```bash
pct snapshot <ctid> test-snapshot
pct listsnapshot <ctid>
pct delsnapshot <ctid> test-snapshot
```

Updated Terraform configs to match:
```hcl
# Before (NFS)
mount_1 = { volume = "nas-dev-data", size = "5G", path = "/opt/ansible" }

# After (local-lvm)
mount_1 = { volume = "local-lvm", size = "5G", path = "/opt/ansible" }
```

Files updated: `terraform/{dev,prod}/proxmox/lxc/{ansible,vault_cluster,nginx,local_runner}/variables.tf`

After manual volume move, synced Terraform state:
```bash
terraform apply -refresh-only
```

Running `terraform plan` directly would show "replace" because Terraform can't
move volumes in-place. Always do manual move first, then refresh state.

Verified: Yes — snapshots work on all containers, mount points on local-lvm.

_____________________________________________________________________

[Risk Level] LOW

Container downtime during volume move (stop/start required).

_____________________________________________________________________

[References]
- terraform/{dev,prod}/proxmox/lxc/*/variables.tf — updated mount point configs
