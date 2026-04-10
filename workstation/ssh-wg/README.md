# SSH Configuration

SSH config templates for workstation access to infrastructure.

## Files

| File | Description |
|------|-------------|
| `ssh-config-template` | SSH config entries for VPN and GitHub |

## Usage

Copy the template to your SSH config:

```bash
cat ssh-config-template >> ~/.ssh/config
```

Update the `EIP` placeholder with actual Elastic IP addresses.

## Hosts Configured

| Host | Purpose |
|------|---------|
| `wg-dev` | WireGuard VPN server (dev) |
| `wg-prod` | WireGuard VPN server (prod) |
| `github.com` | GitHub via port 443 (firewall bypass) |

## Related

- [VPN Setup Guide](../../deployment-docs/vpn-setup-guide.txt)
- [Workstation README](../README.md)
