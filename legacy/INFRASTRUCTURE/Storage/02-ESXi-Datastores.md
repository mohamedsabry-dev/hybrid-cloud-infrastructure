# ESXi Datastore Architecture

> **VMFS and NFS datastore configuration and usage strategy**

---

## Datastore Hierarchy

```
ESXi Master
│
├─ DS_NVME_1 (2TB) ─── Infrastructure VMs
│   ├─ pfSense
│   ├─ vCenter
│   ├─ Veeam
│   ├─ ESXi Production (nested)
│   ├─ ESXi DR (nested)
│   └─ ISO / Templates
│
├─ DS_NVME_2 (2TB) ─── NAS VM Only (Dedicated)
│   └─ NAS VM (Thick Provisioned)
│       └─ Reason: Snapshot safety (requires 2x disk size)
│
└─ NAS_DS_1 (900GB NFS) ─── Production VMs
    ├─ IPA
    ├─ K8s-Master
    ├─ K8s-Worker-1/2/3
    ├─ Vault-1/2/3
    ├─ Ansible
    ├─ Jenkins
    ├─ Grafana
    └─ vCenter Backups
```

---

## DS_NVME_1 - Infrastructure Datastore

**Type**: VMFS datastore backed by thin VMDK

**Physical Location**: NVME1
**Capacity**: ~2TB
**Provisioned**: ~1.52TB (thin allocated)
**Free Space**: ~600GB available

**Provisioning Strategy**: All VMs thin provisioned

**Contents:**

| VM Name | Disk Size | Type | Purpose | Datastore |
|---------|-----------|------|---------|-----------|
| ESXi Production | 150GB | Thin | Nested ESXi | DS_NVME_1 |
| ESXi DR | 150GB | Thin | Nested ESXi (Cold) | DS_NVME_1 |
| vCenter | 500GB | Thin | Cluster management | DS_NVME_1 |
| Veeam | 680GB | Thin | Backup (80GB OS + 600GB Repo) | DS_NVME_1 |
| pfSense | 40GB | Thin | Firewall | DS_NVME_1 |
| ISO Folder | 50GB | N/A | Installation media | DS_NVME_1 |
| VM Templates | 20GB | Thin | Clone sources | DS_NVME_1 |

**Total Provisioned**: ~1.52TB
**Snapshot Safety**: ✅ Safe (all thin provisioned)

---

## DS_NVME_2 - NAS Dedicated Datastore

**Type**: VMFS datastore backed by thin VMDK

**Physical Location**: NVME1
**Capacity**: ~2TB
**Provisioned**: 930GB (NAS VM: 30GB OS + 900GB thick data disk)
**Free Space**: ~1TB available

**Contents:**

| VM Name | OS Disk | Data Disk | Total Allocated | Provisioning | Datastore |
|---------|---------|-----------|-----------------|--------------|-----------|
| NAS VM | 30GB | 900GB | 930GB | Thick | DS_NVME_2 |

**Note:** OS Disk (30GB) is thin provisioned, Data Disk (900GB) is thick provisioned

### Why Dedicated Datastore?

**Thick Provisioning Snapshot Rule:**
- Thick disk requires ≥ 2× disk size for snapshots
- NAS VM: 930GB (30GB thin OS + 900GB thick data) → Requires 2TB datastore (2 × 930GB = ~1.86TB)
- Dedicated datastore ensures snapshot safety

**Why Not Put NAS on DS_NVME_1?**
- ❌ Would consume entire datastore capacity
- ❌ No room for infrastructure VM snapshots
- ❌ Violates 2x disk size rule

**Provisioning Choice: Thick**
- ✅ Predictable performance (no thin overhead)
- ✅ Guaranteed space for NFS storage
- ✅ Simpler management (no over-subscription)
- ⚠️ Requires careful snapshot planning

**Reference:** See troubleshooting case `09-Thick-Provisioned-Snapshot-Size.txt`

---

## NAS_DS - NFS Shared Datastore

**Type**: NFS datastore exported from NAS VM

**Capacity**: 900GB
**Provisioned**: ~780GB (Production VMs)
**Free Space**: ~360GB available
**Over-provisioning**: Safe (all VMs thin provisioned)

**NFS Server**: NAS VM (10.0.20.90)
**Export Path**: `/mnt/shared_storage`
**Mount Point**: NAS_DS

### Why NFS for Production VMs?

**Requirements for ESXi Cluster:**
- ✅ Shared storage enables vMotion
- ✅ VMs portable between ESXi hosts
- ✅ HA heartbeat datastore
- ✅ Single source of truth for VM files

**Alternative Considered:**
- ❌ Local VMDK per ESXi host: No vMotion, no HA
- ❌ Hardware NAS: Too expensive for home lab
- ✅ NFS from VM: Cost-effective, flexible

**Contents (Production VMs on ESXi Nested):**

| VM Name | OS Disk | Data Disks | Total Allocated | Provisioning | Notes |
|---------|---------|------------|-----------------|--------------|-------|
| IPA | 40GB | N/A | 40GB | Thin | FreeIPA (moved to Infrastructure) |
| Vault-1 | 30GB | 2×5GB RAID1 | 40GB | Thin | Secrets Management |
| Vault-2 | 30GB | 2×5GB RAID1 | 40GB | Thin | Secrets Management |
| Vault-3 | 30GB | 2×5GB RAID1 | 40GB | Thin | Secrets Management |
| K8s-Master | 90GB | 2×10GB RAID1 | 110GB | Thin | K8s Control Plane |
| K8s-Worker-1 | 60GB | N/A | 60GB | Thin | K8s Worker Node |
| K8s-Worker-2 | 60GB | N/A | 60GB | Thin | K8s Worker Node |
| K8s-Worker-3 | 60GB | N/A | 60GB | Thin | K8s Worker Node |
| Monitor | 90GB | 40GB | 130GB | Thin | Grafana + Prometheus |
| Ansible | 90GB | 2×5GB RAID1 | 100GB | Thin | Automation |
| Jenkins | 60GB | 40GB | 100GB | Thin | CI/CD Pipeline |

**Total Provisioned**: ~780GB
**vCenter Backups**: Daily backups (max 7 days retention) = ~7GB

**Note**: Total ~787GB fits within 900GB capacity:
- ✅ Thin provisioning reduces actual usage
- ✅ RAID1 mirrors count as allocated but use same space
- ✅ Safe allocation with ~120GB headroom

---

## NAS_DS_2 - HA Heartbeat Datastore

**Type**: NFS datastore exported from NAS VM

**Capacity**: 5GB
**Usage**: Minimal (heartbeat files only)

**NFS Server**: NAS VM (10.0.20.90)
**Export Path**: `/mnt/datastor2`
**Mount Point**: NAS_DS_2

**Purpose:**
ESXi HA cluster requires ≥ 2 datastores for heartbeat redundancy. If network fails, ESXi uses datastore heartbeat to determine if host is alive.

**Why Separate Datastore?**
- ✅ HA requirement (cannot use same datastore as VMs)
- ✅ Small size (only metadata)
- ✅ Isolates heartbeat from VM I/O

---

## Disaster Recovery Storage

### DR Architecture

**Production Storage:**
- Datastore: NAS_DS_1 (NFS)
- VMs: Running on ESXi Production

**DR Storage:**
- Mirror of NAS_DS_1
- VMs: Clones/replicas ready on ESXi DR
- Status: Powered OFF (cold standby)

**DR Activation:**
1. Production ESXi fails
2. Power on ESXi DR
3. Connect NAS_DS_1 (same NFS share)
4. Start critical VMs from DR
5. RTO: 15-20 minutes

**Storage Continuity:**
- NAS VM runs on ESXi Master (always available)
- Both Production and DR ESXi access same NFS share
- VMs portable between hosts (shared storage)

---

## Related Documentation

- [Storage Overview](01-Storage-Overview.md)
- [NAS Configuration](03-NAS-Configuration.md)
- [Provisioning and RAID](04-Provisioning-and-RAID.md)
- [Snapshot Management](05-Snapshot-Management.md)
