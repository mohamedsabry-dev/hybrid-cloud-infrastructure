# Network Documentation

Network configuration for hybrid cloud infrastructure connecting on-premises lab to AWS.

> **A note on what's in git vs on disk.** Device config exports (`config.txt`, `.rsc`), READMEs, the IP plan, and the topology diagram are committed. Device **backups** (`.bin` for the ER605, `.backup` for MikroTik, `.cfg` for the switch), raw **debug logs** from port/flapping investigations, and **vendor PDFs** are all gitignored — they stay on disk for local reference only because backup files embed credentials and PSKs, raw logs can leak fleet internals (MACs, IPs, timing), and vendor PDFs are not mine to redistribute. The relevant folders (`*/backups/`, `switch/fs308gp/logs/`, `*/docs/*.pdf`) are referenced in the per-device READMEs but their contents are excluded from the repo.

---

## Directory Structure

```
network/
├── README.md                     # This file
├── ip-planning.txt               # IP allocations, VLANs, VIPs, worker storage NICs
├── topology.txt                  # Physical topology + traffic flow (current state)
│
├── router/
│   ├── mikrotik/                 # CURRENT primary router (L009UiGS-RM)
│   │   ├── README.md             # Device info, scripts, why MikroTik
│   │   ├── phase1-mgmt-access.rsc  # Initial mgmt access (run on fresh device)
│   │   ├── phase2-dev-services.rsc # Dev VLAN trunk (ether6 → br-dev)
│   │   └── backups/              # RouterOS backups (GITIGNORED — contain keys)
│   │
│   └── er605/                    # RETIRED — historical archive
│       ├── README.md             # "This folder is retired" + why still here
│       ├── config.txt            # ER605 config at retirement
│       ├── backups/*.bin         # (GITIGNORED — TP-Link .bin embeds creds)
│       └── docs/*.pdf            # (GITIGNORED — vendor PDFs, not redistributable)
│
├── switch/
│   └── fs308gp/                  # L2 switch — storage VLAN 40 only now
│       ├── README.md
│       ├── config.txt            # Current layout + HISTORICAL service-VLAN design
│       ├── backups/              # (GITIGNORED — config export with creds)
│       ├── docs/*.pdf            # (GITIGNORED — vendor material)
│       └── logs/                 # (GITIGNORED — raw debug dumps from TS-NET-003)
│
├── ap/
│   └── ac750/                    # WiFi mgmt AP
│       ├── README.md
│       └── config.txt            # AP + unified_mgmt SSID + AP Isolation
│
└── vpn/
    ├── README.md                 # Summary of both tunnels + routing
    ├── wireguard-setup.md        # Detailed setup guide with reasoning
    ├── wireguard-config.txt      # Quick tunnel reference
    └── setup-wireguard.sh        # Automation script for AWS EC2 side
```

See the "what's in git vs on disk" note at the top of this file for why the
backups/, docs/, and switch logs/ folders are gitignored. Per-device READMEs
explain the local-only files in more detail.

---

## Architecture Overview

```
ISP ONT
    │
    ├── MikroTik L009UiGS-RM (Firewall/Router/VPN endpoint)
    │   ├── ether1       → ISP uplink / initial management
    │   ├── ether6        → FS308GP (Dev Services Trunk, VLANs 60-65)
    │   ├── <prod trunk port> → FS308GP (Prod Services Trunk, VLANs 50-55)
    │   └── <mgmt port>   → AC750 AP (WiFi Mgmt — VLAN 5)
    │
    ├── FS308GP (L2 Switch)
    │   ├── VLAN 40 (Storage) → NAS, Proxmox stor0
    │   ├── VLAN 50-55 (Prod) → Prod Proxmox trunk
    │   └── VLAN 60-65 (Dev) → Dev Proxmox trunk
    │
    └── WireGuard VPN (terminated on MikroTik)
        ├── dev_tunnel  → AWS Dev VPC (172.16.0.0/16)
        └── prod_tunnel → AWS Prod VPC (172.17.0.0/16)
```

> The router was previously a TP-Link ER605 — see [`DESIGN.md`](DESIGN.md) for the full evolution story.

---

## VLAN Summary

| VLAN | Range | Purpose | Environment |
|------|-------|---------|-------------|
| 5 | 10.0.5.0/24 | Management (WiFi) | Shared |
| 40 | 10.0.40.0/24 | Storage (NFS) | Shared |
| 50 | 10.0.50.0/24 | Identity (FreeIPA) | Prod |
| 51 | 10.0.51.0/24 | K8s Control Plane | Prod |
| 52 | 10.0.52.0/24 | Vault Cluster | Prod |
| 53 | 10.0.53.0/24 | Management (Ansible, Runner) | Prod |
| 54 | 10.0.54.0/24 | K8s Data Plane | Prod |
| 55 | 10.0.55.0/24 | DMZ (NGINX) | Prod |
| 60 | 10.0.60.0/24 | Identity (FreeIPA) | Dev |
| 61 | 10.0.61.0/24 | K8s Control Plane | Dev |
| 62 | 10.0.62.0/24 | Vault Cluster | Dev |
| 63 | 10.0.63.0/24 | Management (Ansible, Runner) | Dev |
| 64 | 10.0.64.0/24 | K8s Data Plane | Dev |
| 65 | 10.0.65.0/24 | DMZ (NGINX) | Dev |

---

## Key Infrastructure

| Component | Prod IP | Dev IP | Notes |
|-----------|---------|--------|-------|
| FreeIPA | 10.0.50.10 | 10.0.60.10 | DNS server per environment |
| Ansible | 10.0.53.10 | 10.0.63.10 | Configuration management |
| Local Runner | 10.0.53.20 | 10.0.63.20 | GitHub Actions runner |
| Vault Cluster | 10.0.52.10-12 | 10.0.62.10-12 | 3-node HA cluster |
| K8s Masters | 10.0.51.10-12 | 10.0.61.10-12 | 3-node control plane |
| K8s Workers | 10.0.54.10-12 | 10.0.64.10-12 | 3-node data plane |

---

## Device Quick Reference

| Device | Model | Management IP | Documentation |
|--------|-------|---------------|---------------|
| Router | MikroTik L009UiGS-RM | 10.0.5.1 | [router/mikrotik/](router/mikrotik/) |
| Switch | FS308GP | Via Controller | [switch/fs308gp/](switch/fs308gp/) |
| AP | AC750 | 10.0.5.x (DHCP) | [ap/ac750/](ap/ac750/) |
| VPN | WireGuard (on MikroTik) | N/A | [vpn/](vpn/) |
| Router (retired) | TP-Link ER605 v2 | — | [router/er605/](router/er605/) — historical archive |

---

## Known Issues

### (Historical) ER605 "Port 4 defect"

Early in the project I thought the ER605's Port 4 had a gigabit-negotiation defect and moved the Dev trunk cable from Port 4 to Port 2 with a port-mirroring config as a workaround. **Later investigation in TS-NET-003 showed the port was not actually defective** — the real root cause of the link flapping was elsewhere, and the "faulty port" framing was a false trail. Kept here for completeness since some historical configs and backups reference the Port 4 → Port 2 cable move. No longer applicable after the MikroTik migration.

---

## Quick Reference

**Domain:** lab.local

**DNS:** FreeIPA (one per environment)
- Prod: 10.0.50.10
- Dev: 10.0.60.10
- Forwarders: 8.8.8.8, 1.1.1.1

**DHCP Range:** 10.0.X.200 - 10.0.X.220 (per VLAN)

**Management Access:**
- Router (MikroTik): 10.0.5.1
- Prod Proxmox: 10.0.5.100
- Dev Proxmox: 10.0.5.110
- NAS: 10.0.5.120

**VPN Tunnels:** (terminated on MikroTik)
- Dev: 172.16.200.1 (on-prem) ↔ 172.16.200.2 (AWS)
- Prod: 172.17.200.1 (on-prem) ↔ 172.17.200.2 (AWS)
