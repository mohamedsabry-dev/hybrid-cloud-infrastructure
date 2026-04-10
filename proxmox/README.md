# Proxmox Infrastructure

Documentation and scripts for Proxmox VE servers.

## Server Details

| Environment | Hostname | Management IP | Storage IP | API URL |
|-------------|----------|---------------|------------|---------|
| PROD | pve-prod.lab.local | 10.0.5.100 | 10.0.40.100 | https://pve-prod.lab.local:8006 |
| DEV | pve-dev.lab.local | 10.0.5.110 | 10.0.40.110 | https://pve-dev.lab.local:8006 |

## Folder Structure

| Folder | Purpose |
|--------|---------|
| [bootstrap_proxmox/](bootstrap_proxmox/) | Initial Proxmox host setup (bootstrap, network, mail) |
| [golden_templates/](golden_templates/) | VM/LXC golden image preparation scripts |
| [backup/](backup/) | Backup scripts and configuration |
| [disaster_recovery/](disaster_recovery/) | DR guides (power outage, hardware failure, recovery) |
| [storage/](storage/) | NAS storage configuration |
| [network_monitoring/](network_monitoring/) | Network monitoring setup |

## Quick Start

### New Proxmox Installation

```bash
# 1. Bootstrap (repos, users, NTP)
./bootstrap_proxmox/bootstrap.sh dev   # or prod

# 2. Network (WiFi, VLANs, bridges)
./bootstrap_proxmox/network-setup.sh dev   # or prod
reboot

# 3. Optional: Email notifications
./bootstrap_proxmox/mail-config.sh
```

### Create Golden Templates

```bash
# VM: Run inside fresh Rocky Linux VM
./golden_templates/golden-vm-setup.sh

# LXC: Run inside fresh Rocky Linux container
./golden_templates/golden-lxc-setup.sh
```

### Backup Proxmox Config

```bash
# Run on Proxmox host
/root/scripts/backup-proxmox-config.sh
```

