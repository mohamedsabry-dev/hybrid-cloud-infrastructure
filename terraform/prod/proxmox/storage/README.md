# Proxmox Storage — PROD

Terraform module for provisioning NFS storage mounts on the Proxmox host.
Connects the hypervisor to the Asustor NAS (10.0.40.120) for shared ISOs,
env-specific VM/LXC data, and centralized backups.

---

## Modules

| Module | Description |
|--------|-------------|
| `nas` | NFS mounts: shared ISOs, `nas-prod-data`, `nas-backups` |

## Storage layout on the NAS

```
Asustor NAS (10.0.40.120)
│
├── /volume1/shared-iso      → nas-iso         (shared dev + prod)
│   ├── ISO images
│   └── LXC templates (.tar.gz)
│
├── /volume1/dev-storage     → nas-dev-data    (dev only)
│   ├── VM disk images
│   └── LXC rootfs
│
├── /volume1/prod-storage    → nas-prod-data   (prod only)
│   ├── VM disk images
│   └── LXC rootfs
│
└── /volume1/Backups         → nas-backups     (shared dev + prod)
    └── vzdump backups
```

## Storage IDs + content

| Storage ID | Content types | Purpose |
|------------|---------------|---------|
| `nas-iso` | `iso`, `vztmpl` | ISO images + LXC container templates |
| `nas-prod-data` | `images`, `rootdir`, `backup` | VM disks, LXC rootfs, env backups |
| `nas-backups` | `backup`, `rootdir` | Centralized vzdump backups |

## Backup retention (`keep_last`)

| Storage | `keep_last` | Why |
|---------|-------------|-----|
| `nas-prod-data` backup content | 2 | Quick rollback for recent changes |
| `nas-backups` | 5 | Longer retention for disaster recovery |

## Outputs

| Output | Description |
|--------|-------------|
| `nas_iso_id` | Storage ID for ISOs + container templates |
| `nas_data_id` | Storage ID for VM images + container rootfs |
| `backups_id` | Storage ID for vzdump backups |

## Environment differences (dev vs prod)

Only `variables.tf` differs:

| Variable | Dev | Prod |
|----------|-----|------|
| `nas_iso.nodes` | `["pve-dev"]` | `["pve-prod"]` |
| `nas_data.id` | `nas-dev-data` | `nas-prod-data` |
| `nas_data.export` | `/volume1/dev-storage` | `/volume1/prod-storage` |
| `nas_data.nodes` | `["pve-dev"]` | `["pve-prod"]` |
| `backups.nodes` | `["pve-dev"]` | `["pve-prod"]` |
| `proxmox_api_url` | `https://pve-dev.lab.local:8006` | `https://pve-prod.lab.local:8006` |

## Shared storage (same mount on both envs)

- `nas-iso` — same NFS export mounted on both dev and prod Proxmox nodes
- `nas-backups` — centralized backup storage accessible from both environments

## Related

- [`../../../../proxmox/storage/`](../../../../proxmox/storage/) — NAS config on the Proxmox side (design + ops)
- [`../../../../.github/workflows/prod-proxmox-storage.yml`](../../../../.github/workflows/prod-proxmox-storage.yml) — apply workflow
