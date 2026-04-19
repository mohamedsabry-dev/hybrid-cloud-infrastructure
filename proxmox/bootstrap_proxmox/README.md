# Proxmox Bootstrap Scripts

Initial setup scripts for Proxmox VE servers. Run once after fresh Proxmox installation.

> **Design notes & reasoning** — for how these scripts grew from a manual-first run, why `bootstrap.sh` and `network-setup.sh` are split (SSH-disconnect risk), why Terraform gets its own long-lived Proxmox token, and what the scripts deliberately do NOT do, see [`DESIGN.md`](DESIGN.md).

## Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `bootstrap.sh` | Core system setup (repos, users, NTP) | `./bootstrap.sh <dev\|prod>` |
| `network-setup.sh` | Network configuration (WiFi, VLANs, bridges) | `./network-setup.sh <dev\|prod>` |
| `mail-config.sh` | Email notifications via Gmail SMTP | `./mail-config.sh` |

## Setup Order

```bash
# 1. Core system setup (run from console or SSH)
./bootstrap.sh dev    # or prod

# 2. Network configuration (run from console - NOT over WiFi!)
./network-setup.sh dev    # or prod

# 3. Reboot to apply network changes
reboot

# 4. Optional: Configure email notifications
./mail-config.sh
```

## What Each Script Does

### bootstrap.sh

1. Disable sleep/suspend/hibernate
2. Add fallback DNS (8.8.8.8)
3. Disable enterprise repos, enable no-subscription repo
4. APT update & upgrade
5. Remove subscription nag popup
6. Configure Chrony NTP + timezone (Africa/Cairo)
7. Create admin user (`admin_dev` or `admin_prod`)
8. Create Terraform automation user (`tf_dev` or `tf_prod`)

### network-setup.sh

1. Install wpa_supplicant
2. Configure WiFi (unified_mgmt SSID)
3. Test WiFi connectivity
4. Configure `/etc/network/interfaces`:
   - WiFi management interface
   - Service VLAN trunk (vmbr0)
   - Storage VLAN interface
5. Update `/etc/hosts`
6. Regenerate Proxmox SSL certificate

### mail-config.sh

1. Install SASL module
2. Configure Postfix for Gmail SMTP relay
3. Send test email

## Environment Differences

| Setting | Dev | Prod |
|---------|-----|------|
| Admin user | `admin_dev` | `admin_prod` |
| Terraform user | `tf_dev` | `tf_prod` |
| WiFi interface | `wlp1s0` | `wlp4s0` |
| Management IP | `10.0.5.110` | `10.0.5.100` |
| Storage IP | `10.0.40.110` | `10.0.40.100` |
| Service VLANs | `60-65` | `50-55` |
| Hostname | `pve-dev` | `pve-prod` |

## Prerequisites

- Fresh Proxmox VE 9.x installation
- Console or storage network access (for network-setup.sh)
- WiFi password for unified_mgmt network
- Gmail App Password (for mail-config.sh)

## Notes

- **network-setup.sh**: Run from console or storage network, NOT over WiFi (it will disconnect you)
- **mail-config.sh**: Requires Gmail App Password, not regular password
- Scripts are idempotent - safe to re-run if needed
