# Case 3: LXC Container mount_point Bug (Provider 0.93.x)

## Status: RESOLVED
## Date: 2026-03
## Environment: Terraform 1.14.3, bpg/proxmox (initially 0.93.1)
## Affected: Ansible LXC (CTID 2001)

---

## Symptoms

When using the `bpg/proxmox` Terraform provider to manage LXC containers with mount_points, the provider fails to create or track mount_points properly, causing perpetual drift and forced container replacement.

## The Problem

### Symptoms

1. **mount_point not created**: After `terraform apply`, the mount_point block exists in config but container has no mount point
2. **State shows empty**: `terraform.tfstate` shows `"mount_point": []` despite config having mount_point defined
3. **Perpetual replacement**: Every `terraform plan` shows container must be replaced due to mount_point changes
4. **Silent failure**: No error messages - apply reports success but mount_point doesn't exist

### Initial Configuration

```hcl
# main.tf
mount_point {
  volume = var.mount_points.mount_1.volume  # "nas-dev-data"
  size   = var.mount_points.mount_1.size    # "5G"
  path   = var.mount_points.mount_1.path    # "/opt/ansible"
}

# variables.tf
variable "mount_points" {
  default = {
    mount_1 = {
      volume = "nas-dev-data"
      size   = "5G"
      path   = "/opt/ansible"
    }
  }
}
```

### Terraform State (BEFORE fix)

```json
{
  "mount_point": [],  // Empty despite config having mount_point!
}
```

### Terraform Plan Output

```
-/+ resource "proxmox_virtual_environment_container" "ansible" must be replaced
    + mount_point { # forces replacement
        + path   = "/opt/ansible"
        + size   = "5G"
        + volume = "nas-dev-data" # forces replacement
      }
```

## Troubleshooting Attempts

### Attempt 1: Check if NAS Storage Type is the Issue

**Hypothesis:** NFS storage (nas-dev-data) might not support LXC mount_points.

**Test:**
```bash
# Manual mount point creation as root - WORKS
root@pve-dev:~# pct set 2001 -mp0 nas-dev-data:5,mp=/opt/ansible
Formatting '/mnt/pve/nas-dev-data/images/2001/vm-2001-disk-0.raw'...
```

**Result:** Manual creation works. NFS storage supports mount_points.

### Attempt 2: Try local-lvm Instead

**Hypothesis:** Maybe local-lvm works better than NFS.

**Test:** Changed `volume = "local-lvm"` in variables.tf.

**Result:** Same issue - mount_point not created, state empty.

### Attempt 3: Check API Token Permissions

**Hypothesis:** API token might lack permissions for mount operations.

**Test:**
```bash
# As non-root user (similar to API token)
admin_dev@pve-dev:~$ pct set 2001 -mp0 nas-dev-data:6,mp=/opt/ansible2
ipcc_send_rec[1] failed: Unknown error -1
Unable to load access control list: Unknown error -1
```

**Result:** Non-root users cannot create mount_points. But this wasn't the root cause - the provider wasn't even attempting the API call.

### Attempt 4: Reference Existing Volume

**Hypothesis:** Reference a pre-created volume instead of creating new one.

**Steps:**
1. Create volume manually: `pct set 2001 -mp0 local-lvm:5,mp=/opt/ansible`
2. Get volume name: `pct config 2001 | grep mp0` → `local-lvm:vm-2001-disk-1`
3. Reference in Terraform: `volume = "local-lvm:vm-2001-disk-1"`

**Result:** Same issue - Terraform still shows mount_point not in state, triggers replacement.

### Attempt 5: Add mount_point to ignore_changes

**Hypothesis:** Work around by ignoring mount_point changes.

```hcl
lifecycle {
  ignore_changes = [mount_point]
}
```

**Result:** Would work as workaround but not a real solution.

## Root Cause Discovery

### GitHub Issue #1392 - mount_point Implementation Broken

Found issue: https://github.com/bpg/terraform-provider-proxmox/issues/1392

**Maintainer's statement:**
> "Well, the mount point implementation is broken :( The schema does not have the actual 'mount point name' (i.e., mp0, mp1) attribute, so the provider does not know for sure to which mount point each list item belongs."

**Status:** Postponed to v2.0 milestone.

### GitHub Issue #2507 - Regression in 0.93.0

Found issue: https://github.com/bpg/terraform-provider-proxmox/issues/2507

**Problem:** In 0.93.0, adding mount_points to cloned containers forces replacement instead of in-place update.

**Fix:** Merged in PR #2529, released in **v0.94.0**.

Commit: `fix(lxc): provision mount points when cloning containers` (67990d7)

## The Solution

### Step 1: Upgrade Provider Version

Update all `providers.tf` files from `0.93.1` to `0.96.0`:

```hcl
# Before
proxmox = {
  source  = "bpg/proxmox"
  version = "0.93.1"  # Buggy version
}

# After
proxmox = {
  source  = "bpg/proxmox"
  version = "0.96.0"  # Fixed mount_point bug (issue #2507)
}
```

**Files updated:**
- terraform/dev/proxmox/vms/freeipa/providers.tf
- terraform/dev/proxmox/vms/golden-image/providers.tf
- terraform/dev/proxmox/lxc/ansible/providers.tf
- terraform/dev/proxmox/lxc/golden-template/providers.tf
- terraform/prod/proxmox/vms/freeipa/providers.tf
- terraform/prod/proxmox/vms/golden-image/providers.tf
- terraform/prod/proxmox/lxc/ansible/providers.tf
- terraform/prod/proxmox/lxc/golden-template/providers.tf

### Step 2: Update Local Runner Provider Mirror

Provider mirror location: `$HOME/.terraform.d/providers-mirror`

```bash
# On Mac Mini runner (darwin_arm64)
cd ~/.terraform.d/providers-mirror

# Create directory for new version
mkdir -p registry.terraform.io/bpg/proxmox/0.96.0/darwin_arm64
cd registry.terraform.io/bpg/proxmox/0.96.0/darwin_arm64

# Download darwin_arm64 version
curl -LO https://github.com/bpg/terraform-provider-proxmox/releases/download/v0.96.0/terraform-provider-proxmox_0.96.0_darwin_arm64.zip

# Unzip and cleanup
unzip terraform-provider-proxmox_0.96.0_darwin_arm64.zip
rm terraform-provider-proxmox_0.96.0_darwin_arm64.zip
```

### Step 3: Update Runner Documentation

Updated `github/runner-mac-mini.md`:
```markdown
| bpg/proxmox | v0.96.0 | - |
```

### Step 4: Clean Up and Test

```bash
# Remove existing manual mount point
pct set 2001 -delete mp0

# Upgrade provider
terraform init -upgrade

# Plan and apply
terraform plan -out=tfplan
terraform apply tfplan
```

## Validation

### Terraform State (AFTER fix)

```json
{
  "mount_point": [
    {
      "acl": false,
      "backup": false,
      "mount_options": null,
      "path": "/opt/ansible",
      "path_in_datastore": "nas-dev-data:2001/vm-2001-disk-0.raw",
      "quota": false,
      "read_only": false,
      "replicate": true,
      "shared": false,
      "size": "5G",
      "volume": "nas-dev-data:2001/vm-2001-disk-0.raw"
    }
  ]
}
```

### Proxmox Verification

```bash
root@pve-dev:~# pct config 2001 | grep mp0
mp0: nas-dev-data:2001/vm-2001-disk-0.raw,mp=/opt/ansible,size=5G
```

### Container Verification

```bash
[root@ansible ~]# df -h /opt/ansible
Filesystem      Size  Used Avail Use% Mounted on
/dev/sdb        5.0G   68K  5.0G   1% /opt/ansible
```

## Key Takeaways

1. **Provider bugs happen**: Always check GitHub issues when facing unexpected Terraform behavior
2. **Version matters**: Provider 0.93.x had mount_point bugs, fixed in 0.94.0+
3. **Manual testing helps**: `pct set` commands helped isolate that the issue wasn't storage or permissions
4. **Local mirror maintenance**: Self-hosted runners with provider mirrors require manual updates
5. **Document everything**: This troubleshooting took hours - documentation saves time for future issues

## Timeline of Bug

| Version | Status |
|---------|--------|
| < 0.93.0 | mount_point worked (with double-apply workaround) |
| 0.93.0 | Regression - forces replacement |
| 0.93.1 | Still broken |
| 0.94.0 | **Fixed** - PR #2529 merged |
| 0.96.0 | Current stable, confirmed working |

## Related Files

- LXC Ansible: `terraform/dev/proxmox/lxc/ansible/`
- Provider Mirror: `$HOME/.terraform.d/providers-mirror`
- Runner Docs: `github/runner-mac-mini.md`

## Related GitHub Issues

- [#1392 - mount_point implementation broken](https://github.com/bpg/terraform-provider-proxmox/issues/1392)
- [#2507 - Regression in 0.93.0](https://github.com/bpg/terraform-provider-proxmox/issues/2507)
- [#2529 - Fix PR](https://github.com/bpg/terraform-provider-proxmox/pull/2529)
