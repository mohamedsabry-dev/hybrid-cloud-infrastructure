# Route Setup

Persistent route configuration for Mac workstation to reach internal networks.

## Files

| File | Description |
|------|-------------|
| `add-route.sh` | Script to add route to 10.0.0.0/8 network |
| `install-route.sh` | Installer for persistent route via launchd |
| `com.local.route10.plist` | launchd plist for auto-start on boot |

## Purpose

Routes traffic destined for internal networks (10.0.0.0/8) through the local gateway, enabling the Mac workstation to reach Proxmox VMs and LXCs.

## Installation

```bash
# Run the installer (creates launchd service)
sudo bash install-route.sh

# Or manually add route (temporary)
sudo bash add-route.sh
```

## Configuration

Edit `add-route.sh` to set your gateway IP:

```bash
GATEWAY="192.168.100.195"  # Your router/gateway IP
NETWORK="10.0.0.0/8"       # Internal network range
```

## Verification

```bash
# Check if route exists
netstat -rn | grep 10.0.0.0

# Test connectivity
ping 10.0.5.110  # Proxmox host
```

## Related

- [Network Setup Guide](../../deployment-docs/network-setup-guide.txt)
- [Workstation README](../README.md)
