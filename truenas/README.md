# TrueNAS Infrastructure

TrueNAS storage server configuration.

## Structure

```
truenas/
├── terraform/              # VM deployment
├── ansible/                # Config automation (API-based)
├── manual-configs/
│   ├── pool-layouts/       # ZFS pool designs
│   ├── share-configs/      # NFS/SMB share configs
│   └── backup-configs/     # Replication configs
├── docs/
│   ├── zfs-design.md
│   ├── nfs-setup.md
│   └── iscsi-setup.md
├── troubleshooting-cases/
└── scripts/
    └── zfs-monitoring.sh
```

## Services Provided

- NFS shares (VMware datastores, K8s PVs)
- iSCSI targets
- SMB shares (optional)
- ZFS snapshots & replication

## Storage Design

| Pool | Purpose | RAID |
|------|---------|------|
| tank | Primary storage | RAIDZ2 |
| ssd-pool | Fast tier | Mirror |

## Getting Started

```bash
# Access TrueNAS API
curl -X GET "https://truenas.local/api/v2.0/pool" \
  -H "Authorization: Bearer $API_KEY"
```

## Documentation

- [ZFS Design](docs/zfs-design.md)
- [NFS Setup](docs/nfs-setup.md)
- [iSCSI Setup](docs/iscsi-setup.md)
