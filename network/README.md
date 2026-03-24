# Network Documentation

Network configuration for hybrid cloud infrastructure connecting on-premises lab to AWS.

---

## Directory Structure

```
network/
├── ip-planning.txt           # Complete IP allocation and VLAN assignments
├── topology.txt              # Physical topology and traffic flow
├── README.md                 # This file
├── documents/                # General references (official site links)
├── router/
│   ├── er605/                # Current primary router
│   │   ├── config.txt        # Router configuration
│   │   ├── backups/          # Configuration backups (.bin)
│   │   └── docs/             # TP-Link manuals (PDFs)
│   └── mikrotik/             # Upcoming router (L009UiGS-RM)
├── switch/
│   └── fs308gp/              # L2+ managed switch
│       ├── config.txt        # Switch configuration
│       ├── backups/          # Configuration backups
│       ├── docs/             # Controller documentation
│       └── logs/             # Troubleshooting issue logs
├── ap/
│   └── ac750/                # WiFi access point
│       └── config.txt        # AP configuration
└── vpn/
    ├── wireguard-config.txt  # VPN summary
    ├── wireguard-setup.md    # Detailed setup guide
    └── setup-wireguard.sh    # Setup script
```

---

## Architecture Overview

```
ISP ONT
    │
    ├── ER605 (Firewall/Router/VPN)
    │   ├── Port 2 → FS308GP (Dev Services Trunk) *cable moved from Port 4
    │   ├── Port 3 → AC750 AP (WiFi Mgmt - VLAN 5)
    │   ├── Port 4 → UNUSED (defective)
    │   └── Port 5 → FS308GP (Prod Services Trunk)
    │
    ├── FS308GP (L2 Switch)
    │   ├── VLAN 40 (Storage) → NAS, Proxmox stor0
    │   ├── VLAN 50-55 (Prod) → Prod Proxmox trunk
    │   └── VLAN 60-65 (Dev) → Dev Proxmox trunk
    │
    └── WireGuard VPN
        ├── dev_tunnel → AWS Dev VPC (172.16.0.0/16)
        └── prod_tunnel → AWS Prod VPC (172.17.0.0/16)
```

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
| Router | ER605 v2 | 10.0.5.1 | [router/er605/](router/er605/) |
| Switch | FS308GP | Via Controller | [switch/fs308gp/](switch/fs308gp/) |
| AP | AC750 | 10.0.5.x (DHCP) | [ap/ac750/](ap/ac750/) |
| VPN | WireGuard | N/A | [vpn/](vpn/) |

---

## Known Issues

### ER605 Port 4 Defect

Port 4 on the ER605 has a hardware defect causing gigabit negotiation failures.

**Resolution:**
- Enabled port mirroring on router: Port 4 config → Port 2
- Physically moved cable from Port 4 to Port 2
- All router/switch config unchanged, just cable moved
- Port 4 left unused

**Troubleshooting case:** `/troubleshooting/network/48-er605-port4-gigabit-negotiation.md`

---

## Quick Reference

**Domain:** lab.local

**DNS:** FreeIPA (one per environment)
- Prod: 10.0.50.10
- Dev: 10.0.60.10
- Forwarders: 8.8.8.8, 1.1.1.1

**DHCP Range:** 10.0.X.200 - 10.0.X.220 (per VLAN)

**Management Access:**
- ER605: 10.0.5.1
- Prod Proxmox: 10.0.5.100
- Dev Proxmox: 10.0.5.110
- NAS: 10.0.5.120

**VPN Tunnels:**
- Dev: 172.16.200.1 (ER605) ↔ 172.16.200.2 (AWS)
- Prod: 172.17.200.1 (ER605) ↔ 172.17.200.2 (AWS)
