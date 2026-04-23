# TS-PVE-006 | 2026-03-20 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Proxmox VE / Terraform / Backup
Sub-techs: LXC mount points, vzdump backup inclusion, bpg/proxmox provider,
           Terraform defaults, backup=0
Environment: DEV & PROD Proxmox servers
Re-opened: No

_____________________________________________________________________

[Issue Description]
LXC mount points (mp0) showing as "No - Disabled" in backup inclusion list.
Backups completed successfully but silently missed critical data on mount points.

Affected containers (Dev):
| CTID | Name | mp0 Path | Backup Status |
|------|------|----------|---------------|
| 2001 | ansible | /opt/ansible | No - Disabled |
| 2002 | local-runner | /opt/local_runner | No - Disabled |
| 2003 | ex-nginx | /opt/nginx | No - Disabled |
| 2004-2006 | vault1-3 | /opt/vault | No - Disabled |

_____________________________________________________________________

[Analysis]

# Step 1: Discovered in Backup Details UI

Datacenter → Backup → Job Detail → Included disks:
```
2001 (ansible)        lxc
  mp0 - local-lvm:vm-2001-disk-1      No - Disabled
  rootfs - local-lvm:vm-2001-disk-0   Yes
```

# Step 2: Verified via CLI

```bash
pct config 2001 | grep mp0
# mp0: local-lvm:vm-2001-disk-1,mp=/opt/ansible,backup=0,size=5G
```

`backup=0` — mp0 excluded from backups.

# Step 3: Checked Terraform provider docs

bpg/proxmox provider `mount_point` block:
```
backup (Optional) Whether to include the mount point in backups
       (only used for volume mount points, defaults to false).
```

Provider defaults `backup` to `false` if not explicitly set.

_____________________________________________________________________

[Final Root Cause]
Terraform bpg/proxmox provider defaults `mount_point` backup attribute to
`false`. Since this wasn't explicitly set to `true` in Terraform configs, all
mp0 volumes were created with `backup=0`, excluding them from backups.

_____________________________________________________________________

[Final Solution]

Updated Terraform configs to explicitly set `backup = true`:

variables.tf (all LXC modules):
```hcl
variable "mount_points" {
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
      backup = true   # Added
    }
  }
}
```

main.tf (all LXC modules):
```hcl
mount_point {
  volume = var.mount_points.mount_1.volume
  size   = var.mount_points.mount_1.size
  path   = var.mount_points.mount_1.path
  backup = var.mount_points.mount_1.backup  # Added
}
```

Files modified (both dev and prod):
- `terraform/{dev,prod}/proxmox/lxc/{ansible,local_runner,nginx,vault_cluster}/{variables,main}.tf`

Applied in-place — containers keep running:
```bash
terraform plan   # verify only backup attribute changes
terraform apply
```

Verify:
```bash
pct config 2001 | grep mp0
# Expected: mp0: local-lvm:vm-2001-disk-1,mp=/opt/ansible,backup=1,size=5G
```

Verified: Yes — all mount points included in backups, mp0 shows "Yes" in
backup job details.

_____________________________________________________________________

[Risk Level] LOW

In-place update, containers keep running. No downtime.

_____________________________________________________________________

[References]
- TS-PVE-005 — backup missed (discovered during same backup audit)
- terraform/{dev,prod}/proxmox/lxc/*/variables.tf — updated configs
