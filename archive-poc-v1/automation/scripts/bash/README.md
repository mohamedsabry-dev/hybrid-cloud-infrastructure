# Bash Scripts

Linux system administration utilities.

## Scripts

| File | Purpose |
|------|---------|
| `create-emergency-user.sh` | Create emergency admin user with sudo |
| `sshadmin-config-clean.sh` | SSH hardening and admin configuration |
| `pfsense-command-guide.txt` | pfSense CLI command reference |

## Usage

```bash
# Create emergency user
sudo bash create-emergency-user.sh

# Configure SSH admin access
sudo bash sshadmin-config-clean.sh
```

## Related

- [OS services playbooks](../../ansible/os-services/)
- [Emergency shutdown docs](../../../docs/backup/02-emergency-shutdown.md)
