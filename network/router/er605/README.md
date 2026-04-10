# TP-Link ER605 Router

Current primary router/firewall configuration.

## Contents

| Path | Description |
|------|-------------|
| `config.txt` | Router configuration details |
| `backups/` | Configuration backup files (.bin) |
| `docs/` | Official TP-Link documentation (PDFs) |

## Device Info

| Property | Value |
|----------|-------|
| Model | ER605 v2 |
| Firmware | 2.2.0 |
| Management IP | 10.0.5.1 |
| Role | Router/Firewall/VPN Gateway |

## Port Assignments

| Port | Connection | Purpose |
|------|------------|---------|
| WAN | ISP ONT | Internet uplink |
| Port 3 | AC750 AP | WiFi Management (VLAN 5) |
| Port 4 | FS308GP | Dev Services Trunk |
| Port 5 | FS308GP | Prod Services Trunk |

## Backups

Backup naming convention: `backup-ER605_UN_<version>-<date>-<description>.bin`

Example: `backup-ER605_UN_v2.20-2026-03-22-After-Port4-defect-mirror-to-port2.bin`
