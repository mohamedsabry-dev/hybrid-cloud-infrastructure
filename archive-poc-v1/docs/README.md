# Documentation

Technical documentation for POC v1 infrastructure.

## Structure

| Folder | Description | Documents |
|--------|-------------|-----------|
| `backup/` | Veeam backup strategy and emergency procedures | 5 docs |
| `compute/` | VM specifications and resource allocation | 4 docs |
| `failover/` | DR procedures and VM orchestration | 2 docs |
| `identity/` | FreeIPA and user account management | 2 docs |
| `network/` | pfSense, VLANs, vMotion configuration | 7 docs + diagram |
| `storage/` | NAS, datastores, snapshots | 7 docs |

## Quick Links

### Emergency Procedures
- [Emergency Shutdown](backup/02-emergency-shutdown.md)
- [DR Failover Procedures](failover/02-dr-failover-procedures.md)
- [VM Startup/Shutdown Order](failover/01-vm-startup-shutdown.md)

### Infrastructure Reference
- [Network Overview](network/01-network-overview.md)
- [Storage Overview](storage/01-storage-overview.md)
- [VM Specifications](compute/02-vm-specifications-and-decisions.md)

### Identity Management
- [User Accounts](identity/01-user-accounts.md)
- [FreeIPA Configuration](identity/02-identity-management-ipa.md)

## Related

- [Automation scripts](../automation/)
- [Troubleshooting cases](../troubleshooting/)
