# Provisioning Strategy and RAID

> **Thin vs thick provisioning decisions and software RAID configuration**

---

## Thin vs Thick Provisioning

### Thin Provisioning (Default)

**How It Works:**
- Allocates space on demand as data is written
- 100GB disk with 10GB data = 10GB actual storage used
- Snapshot captures only 10GB of actual data

**Use Cases:**
- ✅ All VMs except NAS VM
- ✅ Infrastructure VMs (vCenter, Veeam, pfSense)
- ✅ Production VMs (K8s, Vault, IPA, etc.)

**Benefits:**
- ✅ Efficient space usage
- ✅ Smaller snapshots
- ✅ Easier capacity planning
- ✅ Faster VM creation

**Trade-offs:**
- ⚠️ Slightly slower initial writes
- ⚠️ Risk of datastore over-subscription
- ⚠️ Requires monitoring actual usage

---

### Thick Provisioning (NAS VM Only)

**How It Works:**
- Reserves full disk capacity immediately at creation
- 100GB disk = 100GB storage allocated upfront
- Even with 10GB data, full 100GB reserved

**Use Cases:**
- ✅ NAS VM data disks only (900GB + 5GB = 905GB total)

**Benefits:**
- ✅ Predictable performance (no thin overhead)
- ✅ Guaranteed space (no over-subscription)
- ✅ Simpler management for critical storage

**Trade-offs:**
- ❌ Snapshots capture ENTIRE allocated space
- ❌ 900GB thick disk = 900GB snapshot (not 50GB actual data)
- ❌ Requires dedicated datastore for snapshot safety

### Thick Provisioning Types

| Type | Description | Use Case |
|------|-------------|----------|
| **Lazy Zeroed** | Space reserved, zeroed on first write | General use |
| **Eager Zeroed** | Space reserved and zeroed immediately | FT VMs, paranoid security |

**NAS VM Uses**: Lazy Zeroed (adequate for home lab)

---

## Software RAID Configuration

### Why RAID for Production VMs?

**Data Protection:**
- ✅ Mirror critical data across 2 disks
- ✅ Survive single disk failure
- ✅ Production best practice

**Production VMs with RAID1:**
```
IPA:         30GB OS + 2×20GB RAID1 (LDAP/Kerberos data - critical)
K8s-Master:  90GB OS + 2×60GB RAID1 (cluster state - critical)
Vault-1/2/3: 20GB OS + 2×5GB RAID1 each (secrets - highly critical)
Ansible:     90GB OS + 2×60GB RAID1 (automation code - important)
Jenkins:     90GB OS + 2×20GB RAID1 (build artifacts - important)
Monitoring:  90GB OS + 2×20GB RAID1 (metrics history - important)
```

**Production VMs with RAID1 (Worker Nodes):**
```
K8s-Worker-1: 50GB OS + 2×30GB RAID1 (container workloads)
K8s-Worker-2: 50GB OS + 2×30GB RAID1 (container workloads)
K8s-Worker-3: 50GB OS + 2×30GB RAID1 (container workloads)
```

---

## RAID Impact on Snapshots

**Before RAID Configuration:**
- VM with 50GB disk, 10GB used
- Thin provisioned
- Snapshot: ~10GB (actual data only)

**After RAID Configuration:**
- VM with 2×50GB disks in RAID1
- RAID initializes ENTIRE array (writes metadata)
- Snapshot: ~100GB (full array size)
- Thin provisioning effectively becomes thick

**Lesson Learned:**
Take snapshots BEFORE configuring RAID if testing

**Reference:** See troubleshooting case `09-Thick-Provisioned-Snapshot-Size.txt`

---

## Provisioning Recommendations

### Infrastructure VMs (DS_NVME_1)
```
VM Type         | Provisioning | Reason
────────────────┼──────────────┼─────────────────────────────
pfSense         | Thin         | Small, predictable growth
vCenter         | Thin         | Large but space-efficient
Veeam           | Thin         | Backup repo, efficient
ESXi Nested VMs | Thin         | Multiple VMs, over-provision OK
```

### NAS VM (DS_NVME_2)
```
Disk Type    | Provisioning | Reason
─────────────┼──────────────┼────────────────────────────────
OS Disk      | Thin         | Small, no performance concern
Data Disk 1  | Thick        | Predictable NFS performance
Data Disk 2  | Thick        | HA heartbeat (small size)
```

### Production VMs (NAS_DS NFS)
```
VM Type       | OS Disk | Data Disks     | Provisioning | RAID  | Total   | Reason
──────────────┼─────────┼────────────────┼──────────────┼───────┼─────────┼────────────────────────
IPA           | 30GB    | 2×20GB         | Thin         | RAID1 | 70GB    | Critical LDAP data
K8s Master    | 90GB    | 2×60GB         | Thin         | RAID1 | 210GB   | Critical cluster state
K8s Worker-1  | 50GB    | 2×30GB         | Thin         | RAID1 | 110GB   | Container workloads
K8s Worker-2  | 50GB    | 2×30GB         | Thin         | RAID1 | 110GB   | Container workloads
K8s Worker-3  | 50GB    | 2×30GB         | Thin         | RAID1 | 110GB   | Container workloads
Vault-1       | 20GB    | 2×5GB          | Thin         | RAID1 | 30GB    | Highly critical secrets
Vault-2       | 20GB    | 2×5GB          | Thin         | RAID1 | 30GB    | Highly critical secrets
Vault-3       | 20GB    | 2×5GB          | Thin         | RAID1 | 30GB    | Highly critical secrets
Ansible       | 90GB    | 2×60GB         | Thin         | RAID1 | 210GB   | Automation code
Jenkins       | 90GB    | 2×20GB         | Thin         | RAID1 | 130GB   | Build artifacts
Monitoring    | 90GB    | 2×20GB         | Thin         | RAID1 | 130GB   | Metrics history
```

---

## Best Practices

**DO:**
- ✅ Use thin provisioning by default
- ✅ Use thick provisioning for critical storage (NAS VM)
- ✅ Configure RAID1 for critical data
- ✅ Take snapshots before RAID configuration
- ✅ Monitor datastore space usage regularly

**DON'T:**
- ❌ Over-provision beyond 2.5x capacity
- ❌ Mix thick and thin on same datastore without planning
- ❌ Configure RAID without snapshot space calculation
- ❌ Use thick provisioning unless necessary
- ❌ Forget to calculate 2x disk size for thick snapshots

---

## Related Documentation

- [ESXi Datastores](02-ESXi-Datastores.md)
- [Snapshot Management](05-Snapshot-Management.md)
- [Troubleshooting](07-Troubleshooting.md)
- [Storage Overview](01-Storage-Overview.md)
