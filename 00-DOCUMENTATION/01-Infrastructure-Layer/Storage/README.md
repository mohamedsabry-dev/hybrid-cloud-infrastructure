# Storage Architecture

> **Multi-tier storage design with NFS centralization and disaster recovery**

---

## Overview

The DC-K8s storage architecture uses a three-layer approach: physical NVMe drives, VMware virtual disks (VMDKs), and NFS shared storage. This design balances performance, capacity, and flexibility while supporting nested virtualization and disaster recovery.

**Total Capacity:** 4.5TB physical → 4.2TB virtual (2.3x over-provisioned)

---

## Documents in This Section

### [01-Storage-Overview.md](01-Storage-Overview.md)
Storage strategy, physical disk layout, and architecture summary
- Physical NVMe configuration (3 drives: 2TB + 2TB + 500GB)
- Storage layer hierarchy
- Capacity planning

### [02-ESXi-Datastores.md](02-ESXi-Datastores.md)
ESXi datastore architecture and configuration
- DS_NVME_1 - Infrastructure VMs
- DS_NVME_2 - NAS VM (dedicated)
- NAS_DS_1 - NFS shared storage
- NAS_DS_2 - HA heartbeat

### [03-NAS-Configuration.md](03-NAS-Configuration.md)
NAS VM setup, disk mounting, and NFS exports
- UUID-based mounting (critical!)
- NFS export configuration
- Network bonding setup
- Firewall rules

### [04-Provisioning-and-RAID.md](04-Provisioning-and-RAID.md)
Thin vs thick provisioning, RAID configuration
- Thin provisioning strategy (default)
- Thick provisioning (NAS VM only)
- Software RAID1 for critical data
- Impact on snapshots

### [05-Snapshot-Management.md](05-Snapshot-Management.md)
Snapshot best practices and backup strategy
- Snapshot space calculation
- Create/delete procedures
- Veeam backup configuration
- Snapshots vs backups

### [06-Performance-Monitoring.md](06-Performance-Monitoring.md)
Storage performance tuning and monitoring
- NFS performance tuning
- Disk I/O optimization
- Capacity alerts
- Health checks

### [07-Troubleshooting.md](07-Troubleshooting.md)
Common storage issues and solutions
- VMDK snapshot chain corruption
- NAS VM boot failures (disk race condition)
- Datastore space exhaustion
- References to detailed troubleshooting cases

---

## Quick Reference

### Storage Capacity Summary

| Datastore | Capacity | Used | Free | Purpose |
|-----------|----------|------|------|---------|
| DS_NVME_1 | 2TB | 1.5TB | 500GB | Infrastructure VMs |
| DS_NVME_2 | 2TB | 935GB | 1065GB | NAS VM (dedicated) |
| NAS_DS_1 | 900GB | 780GB allocated | 120GB | Production VMs (NFS) |
| External DR | 500GB | Variable | N/A | Backup repository |

### Key Design Principles

✅ **Centralized NFS storage** for VM portability and vMotion
✅ **Dedicated datastore** for thick-provisioned VMs (snapshot safety)
✅ **UUID-based mounting** prevents disk race conditions
✅ **Thin provisioning** for all VMs except NAS
✅ **Thick provisioning** for NAS VM (predictable performance)
✅ **Multi-layer backups** (Veeam internal + external)

---

## Related Documentation

- [Network Architecture](../Network/)
- [Compute Resources](../Compute/)
- [Troubleshooting Cases](../../../05-TROUBLESHOOTING/cases/storage/)
- [Infrastructure Layer Overview](../README.md)
