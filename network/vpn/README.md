# VPN Configuration

WireGuard VPN setup for hybrid cloud connectivity.

## Contents

| Path | Description |
|------|-------------|
| `wireguard-config.txt` | VPN configuration summary |
| `wireguard-setup.md` | Detailed setup guide |
| `setup-wireguard.sh` | Setup automation script |

## Tunnel Overview

| Tunnel | Local Endpoint | Remote Endpoint | Purpose |
|--------|----------------|-----------------|---------|
| dev_tunnel | 172.16.200.1 (MikroTik) | 172.16.200.2 (AWS) | On-prem ↔ AWS Dev VPC |
| prod_tunnel | 172.17.200.1 (MikroTik) | 172.17.200.2 (AWS) | On-prem ↔ AWS Prod VPC |

## Network Routing

| From | To | Via |
|------|-----|-----|
| 10.0.60.0/24 (Dev On-prem) | 172.16.0.0/16 (AWS Dev VPC) | dev_tunnel |
| 10.0.50.0/24 (Prod On-prem) | 172.17.0.0/16 (AWS Prod VPC) | prod_tunnel |
