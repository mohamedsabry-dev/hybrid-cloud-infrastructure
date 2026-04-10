# Proxmox Disaster Recovery

Guides and scripts for disaster recovery scenarios.

## Categories

| Folder | Scenario | Description |
|--------|----------|-------------|
| [power/](power/) | Power Outage | UPS monitoring, auto-shutdown on battery |
| [hardware/](hardware/) | Hardware Failure | Replace failed adapters, disks, components |
| [recovery/](recovery/) | Full Recovery | Reinstall Proxmox, restore config, import VMs |

## Quick Links

### Power Outage
- [UPS Monitor Script](power/dr_ups_monitor.sh) - Auto-shutdown when battery low
- [UPS Setup Guide](power/README.md) - Installation and configuration

### Hardware Failure
- [USB-Ethernet Adapter Replacement](hardware/usb-ethernet-adapter-replacement.md) - Replace failed network adapters

### Full System Recovery
- [Recovery Guide](recovery/README.md) - Complete Proxmox reinstall and restore

## Prevention

| Item | Location | Purpose |
|------|----------|---------|
| Config backup | `proxmox/backup/backup-proxmox-config.sh` | Backup Proxmox config to NAS |
| VM backups | Proxmox vzdump | Scheduled VM/CT backups |
| Spare adapters | Physical | Keep spare USB-Ethernet adapters ready |

## Emergency Contacts

Update with your relevant contacts:
- Network admin: -
- Storage admin: -
- Cloud (AWS): -
