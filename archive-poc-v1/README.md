# POC v1 - VMware vSphere Homelab (Archived)

**Status:** Archived
**Duration:** ~2 months of active development
**Superseded by:** Proxmox-based infrastructure (current)

---

## Overview

First iteration homelab infrastructure built on VMware vSphere running nested on Windows host with VMware Workstation. After encountering various challenges (documented in 33 troubleshooting cases), pivoted to Proxmox-based architecture.

**This archive is preserved as portfolio material demonstrating hands-on experience with enterprise technologies and real incident handling.**

---

## Technologies Used

| Category | Technologies |
|----------|--------------|
| Virtualization | VMware vCenter 8, ESXi 8, VMware Workstation |
| Backup | Veeam Backup & Replication (dual-instance) |
| Networking | pfSense, VLANs, vMotion |
| Storage | NAS (iSCSI/NFS), ESXi datastores, RAID |
| Identity | FreeIPA, Kerberos, SSSD |
| CI/CD | Jenkins, Ansible |
| Secrets | HashiCorp Vault |
| Monitoring | Prometheus, Grafana |
| Scripting | PowerShell, Bash |

---

## Directory Structure

```
archive-poc-v1/
├── readme.md                 # This file
├── docs/                     # Documentation
│   ├── backup/               # Veeam config, emergency shutdown
│   ├── compute/              # VM specs, resource allocation
│   ├── failover/             # VM orchestration, DR procedures
│   ├── identity/             # FreeIPA, user accounts
│   ├── network/              # pfSense, VLANs, vMotion
│   └── storage/              # NAS, datastores, snapshots
├── automation/
│   ├── ansible/              # Playbooks (ipa, vault, cicd, monitor)
│   └── scripts/
│       ├── bash/             # Bash scripts
│       └── powershell/       # PowerShell DR automation
└── troubleshooting/          # 31 incident cases
    ├── platform/             # vCenter, ESXi, FreeIPA (15 cases)
    ├── storage/              # Snapshots, NAS, corruption (10 cases)
    ├── network/              # pfSense, loops, routing (5 cases)
    └── application/          # Prometheus (1 case)
```

---

## Key Documentation

| Document | Description |
|----------|-------------|
| `docs/backup/` | Dual Veeam architecture, emergency shutdown |
| `docs/failover/` | VM startup/shutdown, DR procedures |
| `docs/identity/` | FreeIPA users, service accounts |
| `docs/network/` | pfSense setup with VLANs |
| `docs/storage/` | NAS config, VMware snapshot best practices |

---

## Troubleshooting Highlights

31 real incidents documented with root cause analysis:

- **VMDK Snapshot Corruption** - Snapshot chain breakage from cross-partition vDisks
- **Disk Race Condition** - /dev/sdX vs UUID mounting disaster
- **Clock Skew Issues** - Kerberos failures from VMware Tools time sync
- **Network Loops** - Windows IP forwarding causing duplicate packets
- **Veeam AAP Errors** - Application-aware backup causing I/O errors

---

## Why Archived?

**Problems with this architecture:**
- Windows host running VMware Workstation (not ideal)
- Nested virtualization (ESXi inside Workstation)
- Power management issues (laptop UPS, sleep/wake problems)
- Complexity of dual Veeam instances

**Current infrastructure uses:**
- Proxmox VE on bare-metal
- Native virtualization (no nesting)
- Better power management with native Linux tools

---

## Related

- Current infrastructure: See `/deployment-docs/`
- Current troubleshooting: See `/troubleshooting/`
