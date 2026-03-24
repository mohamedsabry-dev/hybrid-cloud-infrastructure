# TP-Link FS308GP Switch

L2+ managed switch configuration for VLAN segmentation.

## Contents

| Path | Description |
|------|-------------|
| `config.txt` | Switch configuration details |
| `backups/` | Configuration backup files |
| `docs/` | Controller documentation |
| `logs/` | Troubleshooting logs for switch issues |

## Device Info

| Property | Value |
|----------|-------|
| Model | FS308GP |
| Type | L2+ Managed Switch with PoE+ |
| Ports | 8 Gigabit + 2 SFP |
| PoE Budget | 62W |

## VLAN Trunk Configuration

| Port | Connection | VLANs |
|------|------------|-------|
| Port 4 | ER605 Port 4 | Dev VLANs (60-65) |
| Port 5 | ER605 Port 5 | Prod VLANs (50-55) |
| Port 6 | Prod Proxmox | 5, 40, 50-55 |
| Port 7 | Dev Proxmox | 5, 40, 60-65 |
| Port 8 | NAS | 5, 40 |

## Troubleshooting Logs

| Folder | Issue |
|--------|-------|
| `Issue1_port3_flapping_Switch/` | Port 3 flapping - includes both router and switch logs |
| `Issue2_port4_flapping_Switch/` | Port 4 flapping investigation |
