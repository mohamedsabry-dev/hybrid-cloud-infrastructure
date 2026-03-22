# Proxmox Storage

This directory contains Terraform modules for provisioning NFS storage mounts on Proxmox.

## Modules

| Module | Description |
|--------|-------------|
| `nas` | NFS storage mounts for ISO images, VM/LXC data, and backups |

## Storage Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Synology NAS (10.0.40.120)                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  /volume1/shared-iso     → nas-iso (shared dev+prod)            │
│  ├── ISO images                                                 │
│  └── LXC templates (.tar.gz)                                    │
│                                                                 │
│  /volume1/dev-storage    → nas-dev-data                         │
│  ├── VM disk images                                             │
│  └── LXC rootfs                                                 │
│                                                                 │
│  /volume1/prod-storage   → nas-prod-data                        │
│  ├── VM disk images                                             │
│  └── LXC rootfs                                                 │
│                                                                 │
│  /volume1/Backups        → nas-backups (shared dev+prod)        │
│  └── vzdump backups                                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Storage Types

| Storage ID | Content Types | Purpose |
|------------|---------------|---------|
| `nas-iso` | `iso`, `vztmpl` | ISO images for VM installation, LXC container templates |
| `nas-dev-data` / `nas-prod-data` | `images`, `rootdir`, `backup` | VM disk images, LXC rootfs, environment-specific backups |
| `nas-backups` | `backup`, `rootdir` | Centralized vzdump backups for disaster recovery |

## Backup Retention

| Storage | `keep_last` | Purpose |
|---------|-------------|---------|
| `nas-data` | 2 | Quick rollback for recent changes |
| `nas-backups` | 5 | Longer retention for disaster recovery |

## Variable Structure

Each storage mount uses the object pattern:

```hcl
variable "nas_iso" {
  type = object({
    id      = string       # Proxmox storage ID
    server  = string       # NFS server IP
    export  = string       # NFS export path
    nodes   = list(string) # Proxmox nodes to mount on
    content = list(string) # Content types (iso, vztmpl, images, rootdir, backup)
  })
}

# For data/backup storage, includes retention:
variable "nas_data" {
  type = object({
    # ... same as above ...
    keep_last = number     # Backup retention count
  })
}
```

## Module Outputs

| Output | Description |
|--------|-------------|
| `nas_iso_id` | Storage ID for ISO images and container templates |
| `nas_data_id` | Storage ID for VM images and container rootfs |
| `backups_id` | Storage ID for vzdump backups |

## Environment Differences

Only `variables.tf` differs between dev and prod:

| Variable | Dev | Prod |
|----------|-----|------|
| `nas_iso.nodes` | `["pve-dev"]` | `["pve-prod"]` |
| `nas_data.id` | `nas-dev-data` | `nas-prod-data` |
| `nas_data.export` | `/volume1/dev-storage` | `/volume1/prod-storage` |
| `nas_data.nodes` | `["pve-dev"]` | `["pve-prod"]` |
| `backups.nodes` | `["pve-dev"]` | `["pve-prod"]` |
| `proxmox_api_url` | `https://pve-dev.lab.local:8006` | `https://pve-prod.lab.local:8006` |

## Shared Storage

The following storage is shared across environments:
- **nas-iso**: Same NFS export mounted on both dev and prod nodes
- **nas-backups**: Centralized backup storage accessible from both environments
