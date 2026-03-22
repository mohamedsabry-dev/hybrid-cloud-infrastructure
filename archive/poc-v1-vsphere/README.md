# POC v1 - VMware vSphere Homelab (Archived)

**Status:** Archived (Superseded by Proxmox-based infrastructure)
**Duration:** ~2 months of active development
**Archived:** March 2026

## Overview

This was the first iteration of my homelab infrastructure, built on VMware vSphere running on a Windows host with VMware Workstation. After 2 months of development and encountering various challenges (documented in 34+ troubleshooting cases), I pivoted to a Proxmox-based architecture which is now the active infrastructure.

**This archive is preserved as portfolio material demonstrating hands-on experience with enterprise technologies and real incident handling.**

## Technologies

| Category | Technologies |
|----------|--------------|
| **Virtualization** | VMware vCenter 8, ESXi 8, VMware Workstation |
| **Backup** | Veeam Backup & Replication (dual-instance architecture) |
| **Networking** | pfSense, VLANs, vMotion, NAS bonding |
| **Storage** | NAS (iSCSI/NFS), ESXi datastores, RAID |
| **Identity** | FreeIPA, Kerberos, SSSD |
| **CI/CD** | Jenkins, Ansible |
| **Secrets** | HashiCorp Vault |
| **Monitoring** | Prometheus, Grafana |
| **Scripting** | PowerShell, Bash, Python |
| **IaC** | Terraform (vSphere + AWS providers) |

## Repository Structure

```
poc-v1-vsphere/
├── infrastructure/           # Core documentation (25+ docs)
│   ├── backup-dr/            # Veeam + disaster recovery
│   ├── compute/              # VM specifications + best practices
│   ├── network/              # pfSense, VLANs, vMotion
│   ├── storage/              # NAS, ESXi datastores, RAID
│   └── dr/                   # DR scripts
├── troubleshooting/          # 34 real incident cases
│   ├── platform/             # vCenter, ESXi, FreeIPA issues
│   ├── network/              # pfSense, loops, routing
│   ├── storage/              # Snapshots, NAS, corruption
│   └── application/          # Jenkins, Prometheus, Git
├── ansible/                  # Configuration management
│   ├── playbooks/            # IPA, Jenkins, Vault, monitoring
│   └── inventory/
├── terraform/                # Infrastructure as Code
│   └── environments/
│       ├── vsphere/          # vSphere provider configs
│       └── aws/              # AWS state backend
├── scripts/                  # Utility scripts
└── docs/                     # Planning documents
```

## Highlights

### Infrastructure Documentation

| Document | Description |
|----------|-------------|
| `infrastructure/backup-dr/` | **Dual Veeam architecture** - Outer (Windows host) + Inner (vCenter) backup instances |
| `infrastructure/backup-dr/02-Emergency-Shutdown.md` | Battery monitoring + automated graceful shutdown |
| `infrastructure/backup-dr/03-Recovery-Procedures.md` | Step-by-step restore workflows for various failure scenarios |
| `infrastructure/network/05-pfSense-Configuration.md` | Complete pfSense setup with VLANs |
| `infrastructure/storage/05-Snapshot-Management.md` | VMware snapshot best practices |
| `infrastructure/compute/02-VM-Specifications-and-Decisions.md` | VM sizing decisions with rationale |

### Troubleshooting Cases (34 Real Incidents)

#### Platform (16 cases)
- vCenter installation, certificates, SSO
- ESXi snapshot performance issues
- FreeIPA time sync and SSSD cache
- VMware Workstation / Hyper-V conflicts

#### Storage (10 cases)
- VMDK snapshot corruption and recovery
- NAS memory starvation
- Thick-to-thin conversion
- Snapshot chain corruption

#### Network (5 cases)
- pfSense power-off issues
- Duplicate packets / network loops
- NAT vs Bridge decisions
- Static route loops

#### Application (3 cases)
- Prometheus setup issues
- Jenkins Docker compatibility
- Git sensitive file removal

### PowerShell Automation

| Script | Purpose |
|--------|---------|
| `BatteryMonitor.ps1` | Monitors UPS battery, triggers shutdown |
| `EmergencyLabShutdown.ps1` | Orchestrated VM shutdown sequence |
| `Test-VeeamStop*.ps1` | Veeam job termination scripts |

## Why Archived?

This infrastructure was built on:
- **Windows host** running VMware Workstation (not ideal for homelab)
- **Nested virtualization** (ESXi inside Workstation)
- **Power management issues** (laptop UPS, sleep/wake problems)

The current infrastructure uses:
- **Proxmox VE** on bare-metal laptops
- **Native virtualization** (no nesting)
- **Better power management** with native Linux tools

## Lessons Learned

1. **Nested virtualization adds complexity** - Many issues traced to VMware-in-VMware
2. **Windows host networking** - NAT/Bridge conflicts, sleep breaking connections
3. **Veeam is powerful but complex** - Dual-instance architecture was overkill
4. **Document everything** - These 34 TS cases saved hours during the rebuild

## Related

- Current infrastructure: See root `Re-Deployment Guide.txt`
- Current troubleshooting: See `/troubleshooting/` (Proxmox-focused)
