# Layer 0: Infrastructure Foundation

**The Outer Layer - Physical and Virtualization Infrastructure**

This layer covers the foundational infrastructure that everything else runs on - the "hardware" layer of your datacenter.

---

## Overview

The Infrastructure Foundation provides:
- Hypervisor platform (ESXi)
- Centralized management (vCenter)
- Shared storage (NAS)
- Network infrastructure (vSwitches, port groups)
- Network security (pfSense)
- Backup infrastructure (Veeam)

---

## Components

### 01. ESXi Hypervisors
- ESXi Master (on VMware Workstation)
- Nested ESXi hosts
- Host configuration
- Network setup

### 02. vCenter Management
- vCenter deployment
- Cluster configuration
- HA/DRS setup
- vApp orchestration

### 03. Storage (NAS)
- NAS VM setup
- NFS shares
- Datastore configuration
- vDisk management

### 04. Network Infrastructure
- vSwitch configuration
- Port groups
- Physical network adapters
- VLAN setup (if applicable)

### 05. pfSense Firewall
- Network gateway
- Firewall rules
- NAT configuration
- Internal network segmentation

### 06. Backup (Veeam)
- Veeam VM setup
- Backup repositories
- Backup jobs configuration
- Backup copy jobs

### 07. vCenter Backup
- Automated vCenter backup
- Backup schedule
- Retention policies

---

## Build Order

1. ESXi Master
2. NAS VM (for shared storage)
3. vCenter
4. Nested ESXi hosts
5. Cluster configuration
6. pfSense VM
7. Veeam VM
8. vCenter backup configuration

---

## Network Architecture

### External Network (192.168.0.0/24)
- Management access
- Internet connectivity

### Internal Network (10.0.20.0/24)
- Production VMs
- Service network

---

## Prerequisites

- Windows 11 host
- VMware Workstation Pro
- Minimum 32GB RAM (64GB recommended)
- 500GB+ storage

---

## Next Steps

After completing this layer, proceed to:
- **[01-PLATFORM-SERVICES](../01-PLATFORM-SERVICES/README.md)** - Identity and automation
