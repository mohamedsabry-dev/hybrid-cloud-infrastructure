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
    ├── wireguard-setup-guide.txt        # Detailed setup guide with reasoning
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

Full VLAN breakdown and all IP allocations: [`ip-planning.txt`](ip-planning.txt)

---

## Device Quick Reference

| Device | Model | Management IP | Documentation |
|--------|-------|---------------|---------------|
| Router | MikroTik L009UiGS-RM | 10.0.5.1 | [router/mikrotik/](router/mikrotik/) |
| Switch | FS308GP | Via Controller | [switch/fs308gp/](switch/fs308gp/) |
| AP | AC750 | 10.0.5.x (DHCP) | [ap/ac750/](ap/ac750/) |
| VPN | WireGuard (on MikroTik) | N/A | [vpn/](vpn/) |
| Router (retired) | TP-Link ER605 v2 | — | [router/er605/](router/er605/) — historical archive |

