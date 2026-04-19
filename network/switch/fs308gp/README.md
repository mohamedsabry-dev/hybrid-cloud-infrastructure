# Festa FS308GP Switch

L2+ managed switch — VLAN segmentation, PoE, and the backbone between the router and the two Proxmox servers.

## Contents

| Path | Description | In git? |
|------|-------------|---------|
| `config.txt` | Switch configuration details | Yes |
| `backups/` | Configuration backup files | No — gitignored (may contain credentials) |
| `docs/` | Vendor / controller documentation PDFs | No — gitignored (vendor material, not redistributable) |
| `logs/` | Troubleshooting log dumps from switch-port flapping investigations | No — gitignored (raw system logs can contain MACs, IPs, and other fleet internals) |

> The `backups/`, `docs/`, and `logs/` folders exist locally but are excluded from git for security/privacy reasons (see `.gitignore` lines for `network/**/backups`, `network/**/logs`, `network/**/docs/*.pdf`). They are kept on disk for local reference and for my own future debugging.

## Device info

| Property | Value |
|----------|-------|
| Model | FS308GP |
| Type | L2+ managed switch with PoE+ |
| Ports | 8 Gigabit + 2 SFP |
| PoE Budget | 62W |

## VLAN trunk configuration

| Port | Connection | VLANs |
|------|------------|-------|
| Port 4 | Router — Dev trunk (MikroTik `ether6`) | Dev VLANs (60-65) |
| Port 5 | Router — Prod trunk (MikroTik) | Prod VLANs (50-55) |
| Port 6 | Prod Proxmox server (service trunk) | 5, 40, 50-55 |
| Port 7 | Dev Proxmox server (service trunk) | 5, 40, 60-65 |
| Port 8 | NAS | 5, 40 |

> Ports 4 and 5 previously terminated at the ER605 router (now retired — see [`../../router/er605/`](../../router/er605/)). Current router is the MikroTik L009UiGS-RM; see [`../../router/mikrotik/`](../../router/mikrotik/).

## Troubleshooting log folders (local only, gitignored)

| Folder | Issue investigated |
|--------|---------------------|
| `logs/Issue1_port3_flapping_Switch/` | Port 3 flapping — includes both router and switch-side logs |
| `logs/Issue2_port4_flapping_Switch/` | Port 4 flapping investigation (ties into TS-NET-003 in `/troubleshooting/network/`) |
| `logs/log/`, `logs/newlog/` | Raw baseline controller dumps for diff reference |

The folders themselves are gitignored; the resolved findings are summarised in the corresponding TS cases under [`../../../troubleshooting/network/`](../../../troubleshooting/network/).
