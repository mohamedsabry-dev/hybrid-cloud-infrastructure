# Storage Overview

> **Physical disk strategy and storage layer hierarchy**

---

## Overview

The DC-K8s storage architecture uses a three-layer approach: physical NVMe drives, VMware virtual disks (VMDKs), and NFS shared storage. This design balances performance, capacity, and flexibility while supporting nested virtualization and disaster recovery.

---

## Storage Summary

### Physical Storage: 4.5TB Total

| Device | Capacity | Purpose | Location | Free Space |
|--------|----------|---------|----------|------------|
| **NVME0** | 2TB | Windows 11 OS + Personal Data | C:\ (Internal) | ~500GB |
| **NVME1** | 2TB | All VMware virtual disks | D:\Virtual Machines (Internal) | ~600GB |
| **NVME2** | 500GB | DR backups + offsite repository | E:\Backup (External USB/Thunderbolt) | ~200GB |

### Virtual Storage Layers

```
Physical Layer (4.5TB)
  ↓
VMDK Layer (4.2TB thin provisioned)
  ↓
Datastore Layer (ESXi datastores)
  ↓
NFS Layer (Centralized VM storage)
```

---

## Physical Disk Layout

### NVME0 - 2TB (Windows Host)

**Purpose**: Windows 11 Pro Host OS & Personal Files

**Partitioning:**
```
C:\ - Windows 11 Pro
  ├─ System Files
  ├─ Applications
  └─ Personal Data
```

**Not used for VMware**: Keeps host and virtualization separate

---

### NVME1 - 2TB (VMware Workstation)

**Purpose**: All VMware Workstation virtual disks

**Layout:**
```
VMware Workstation Virtual Disks/
│
├─ ESXi-Master/
│   └─ ESXi-Master.vmdk (150GB Thin)
│
├─ vDisk_NVME_DS_1/
│   └─ nvme_ds_1.vmdk (2TB Thin)
│       └─ ESXi Datastore: DS_NVME_1
│           ├─ pfSense VM (40GB)
│           ├─ vCenter VM (~500GB)
│           ├─ Veeam VM (80GB OS + 600GB repository)
│           ├─ ESXi Production VM (150GB)
│           ├─ ESXi DR VM (150GB)
│           ├─ ISO Folder
│           └─ VM Templates
│
└─ vDisk_NVME_DS_2/
    └─ nvme_ds_2.vmdk (2TB Thin)
        └─ ESXi Datastore: DS_NVME_2
            └─ NAS VM (980GB Thick Provisioned)
                ├─ OS: 30GB
                └─ Data Disks: 900GB + 5GB
```

**Total Allocated**: ~4.2TB (thin provisioned)
**Actual Usage**: ~2.4TB
**Over-provisioning Ratio**: ~2.3x (4.2TB allocated / 1.8TB physical available = safe with monitoring)

---

### NVME2 - 500GB (External - DR)

**Purpose**: Offsite Disaster Recovery

**Configuration:**
```
External Drive (USB/Thunderbolt)
  └─ Windows Host SMB Share: //10.0.20.1/Backups
      └─ Veeam Backup Copy Jobs
          ├─ Daily incremental backups
          ├─ Weekly full backups
          └─ Retention: 4 weeks
```

**Benefits:**
- ✅ Offsite protection (removable drive)
- ✅ Survives laptop failure
- ✅ Fast restore from local repository
- ✅ Slower restore from external if needed

---

## Capacity Summary

**Total Physical Capacity:** 4.5TB
- NVME0: 2TB (Windows OS + Personal)
- NVME1: 2TB (VMware VMs)
- NVME2: 500GB (DR backups)

**Virtual Allocation:** 4.2TB (thin provisioned)
- DS_NVME_1: ~1.52TB provisioned / ~2TB capacity (~600GB free) - Thin Provisioned
- DS_NVME_2: ~930GB provisioned / ~2TB capacity (~1TB free) - Thick Provisioned (NAS VM)
- NAS_DS (NFS): ~780GB provisioned / 900GB capacity (~360GB free) - Thin Provisioned
- Over-provisioning: ~2.3x ratio (safe with monitoring)

**Actual Usage:** ~2.4TB

---

## Related Documentation

- [ESXi Datastores](02-ESXi-Datastores.md)
- [NAS Configuration](03-NAS-Configuration.md)
- [Provisioning and RAID](04-Provisioning-and-RAID.md)
- [Infrastructure Layer Overview](../README.md)
