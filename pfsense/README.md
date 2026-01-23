# pfSense Infrastructure

pfSense firewall/router configuration and documentation.

## Structure

```
pfsense/
├── terraform/              # VM deployment (via vSphere)
├── ansible/                # Initial config automation
├── manual-configs/         # Mostly manual for pfSense
│   ├── backup-configs/     # XML config exports
│   ├── firewall-rules/     # Rule documentation
│   ├── vpn-configs/        # VPN configurations
│   └── screenshots/        # GUI screenshots
├── docs/
│   ├── setup-guide.md
│   ├── rule-documentation.md
│   └── vpn-setup.md
├── troubleshooting-cases/
├── scripts/
└── exports/                # Config backups
```

## Key Functions

- Internet gateway
- Site-to-site VPN (AWS <-> On-prem)
- Firewall rules
- NAT/routing
- DHCP (optional)

## Backup

```bash
# Backup script location
./scripts/backup-pfsense.sh
```

## Documentation

- [Setup Guide](docs/setup-guide.md)
- [Firewall Rules](docs/rule-documentation.md)
- [VPN Setup](docs/vpn-setup.md)
