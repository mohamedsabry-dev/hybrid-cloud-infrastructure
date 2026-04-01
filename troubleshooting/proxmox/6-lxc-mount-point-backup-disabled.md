# LXC Mount Point (mp0) Not Included in Proxmox Backups

## Issue ID: 38
## Date: 2026-03-20
## Environment: Dev & Prod (pve-dev, pve-prod)
## Status: Resolved

---

## Problem Description

While reviewing Proxmox backup job details, discovered that LXC mount points (mp0) were showing as "No - Disabled" in the backup inclusion list. This means additional storage volumes attached to LXC containers were NOT being backed up.

### Symptoms
- Backup Details showing mp0 disks with "No - Disabled" status
- Only rootfs being included in backups
- No errors in backup logs (silent data loss risk)

### Affected Containers (Dev)
| CTID | Name | mp0 Path | Backup Status |
|------|------|----------|---------------|
| 2001 | ansible | /opt/ansible | No - Disabled |
| 2002 | local-runner | /opt/local_runner | No - Disabled |
| 2003 | ex-nginx | /opt/nginx | No - Disabled |
| 2004-2006 | vault1-3 | /opt/vault | No - Disabled |

### Affected Containers (Prod)
Same pattern - all LXC mp0 volumes had backup disabled.

---

## Investigation

### Step 1: Discovered Issue in Backup Details UI

Opened Datacenter → Backup → Selected backup job → "Job Detail" → "Included disks"

Screenshot showed:
```
2001 (ansible)        lxc
  mp0 - local-lvm:vm-2001-disk-1      No - Disabled
  rootfs - local-lvm:vm-2001-disk-0   Yes
```

### Step 2: Verified via CLI

```bash
# SSH to Proxmox host
pct config 2001 | grep mp0
# Output: mp0: local-lvm:vm-2001-disk-1,mp=/opt/ansible,backup=0,size=5G
```

The `backup=0` setting confirms mp0 is excluded from backups.

### Step 3: Attempted Manual Fix via Web UI

Tried: Select LXC → Resources → mp0 → Edit → Check "Backup"

Found the checkbox but decided against manual fix for reproducibility reasons.

### Step 4: Checked Terraform Provider Documentation

Reviewed bpg/proxmox provider docs for `mount_point` block:

```
backup (Optional) Whether to include the mount point in backups
       (only used for volume mount points, defaults to false).
```

**Root Cause Identified**: The Terraform provider defaults `backup` to `false` if not explicitly set.

---

## Root Cause

When creating LXC containers via Terraform with the bpg/proxmox provider, the `mount_point` block's `backup` attribute defaults to `false`. Since this wasn't explicitly set to `true` in our Terraform configurations, all mp0 volumes were created with `backup=0`.

This is a silent failure - backups complete successfully but miss critical data stored on mount points.

---

## Resolution

### Approach: Update Terraform Configuration

Rather than manually fixing via CLI/UI (not reproducible), updated all Terraform LXC configurations to explicitly set `backup = true`.

### Changes Made

**1. Updated variables.tf (all LXC modules)**

Added `backup = bool` to mount_points object type:

```hcl
variable "mount_points" {
  description = "Map of mount point configurations for the LXC"
  type = map(object({
    volume = string
    size   = string
    path   = string
    backup = bool    # Added
  }))

  default = {
    mount_1 = {
      volume = "local-lvm"
      size   = "5G"
      path   = "/opt/ansible"
      backup = true   # Added - enable backup by default
    }
  }
}
```

**2. Updated main.tf (all LXC modules)**

Added backup attribute to mount_point block:

```hcl
mount_point {
  volume = var.mount_points.mount_1.volume
  size   = var.mount_points.mount_1.size
  path   = var.mount_points.mount_1.path
  backup = var.mount_points.mount_1.backup  # Added
}
```

### Files Modified

**Dev Environment:**
- `terraform/dev/proxmox/lxc/ansible/variables.tf`
- `terraform/dev/proxmox/lxc/ansible/main.tf`
- `terraform/dev/proxmox/lxc/local_runner/variables.tf`
- `terraform/dev/proxmox/lxc/local_runner/main.tf`
- `terraform/dev/proxmox/lxc/nginx/variables.tf`
- `terraform/dev/proxmox/lxc/nginx/main.tf`
- `terraform/dev/proxmox/lxc/vault_cluster/variables.tf`
- `terraform/dev/proxmox/lxc/vault_cluster/main.tf`

**Prod Environment:**
- `terraform/prod/proxmox/lxc/ansible/variables.tf`
- `terraform/prod/proxmox/lxc/ansible/main.tf`
- `terraform/prod/proxmox/lxc/local_runner/variables.tf`
- `terraform/prod/proxmox/lxc/local_runner/main.tf`
- `terraform/prod/proxmox/lxc/nginx/variables.tf`
- `terraform/prod/proxmox/lxc/nginx/main.tf`
- `terraform/prod/proxmox/lxc/vault_cluster/variables.tf`
- `terraform/prod/proxmox/lxc/vault_cluster/main.tf`

### Apply Changes

```bash
# For each LXC module
cd terraform/dev/proxmox/lxc/ansible
terraform plan   # Verify only backup attribute changes
terraform apply  # In-place update, no container restart
```

The change is applied in-place - containers keep running.

---

## Verification

After `terraform apply`:

```bash
# Verify mp0 now has backup=1
pct config 2001 | grep mp0
# Expected: mp0: local-lvm:vm-2001-disk-1,mp=/opt/ansible,backup=1,size=5G

# Or check via backup job details in Web UI
# Datacenter → Backup → Job Detail → Included disks
# mp0 should now show "Yes" instead of "No - Disabled"
```

---

## Prevention

### For New LXC Modules

Always explicitly set `backup = true` in mount_point configurations:

```hcl
mount_point {
  volume = var.mount_points.mount_1.volume
  size   = var.mount_points.mount_1.size
  path   = var.mount_points.mount_1.path
  backup = true  # Always set explicitly
}
```

### Periodic Audit

Check backup job details periodically to ensure all disks show "Yes" for backup inclusion.

---

## Lessons Learned

1. **Don't trust defaults** - Always check provider documentation for default values, especially for backup-related settings
2. **Silent failures are dangerous** - Backup jobs completed successfully but missed critical data
3. **Infrastructure as Code benefits** - Rather than manual CLI fixes, updating Terraform ensures consistency and reproducibility
4. **Review backup scope** - Regularly verify what's actually being backed up, not just that backups run

---

## Related Issues

- [37-proxmox-backup-missed-not-retried.md](./37-proxmox-backup-missed-not-retried.md) - Missing `repeat-missed` flag

## References

- [bpg/proxmox Provider - mount_point](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_container#mount_point)
- [Proxmox VE - Container Backup](https://pve.proxmox.com/wiki/Backup_and_Restore)
