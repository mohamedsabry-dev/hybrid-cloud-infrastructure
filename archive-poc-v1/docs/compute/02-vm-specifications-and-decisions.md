# VM Specifications and Architectural Decisions

> **Detailed VM resource allocation and key design decisions**

---

## Infrastructure Layer VMs (ESXi Master)

### NAS VM - Storage Server
```
Memory:  8GB (increased from 8GB for concurrent backup operations)
CPU:     4 vCPU
Disk:    30GB OS + 900GB data (Thick provisioned)
Network: 2 vNIC bonded (Active-Backup, bond0)
IP:      10.0.20.90
FQDN:    nas.home.lab
Purpose: Centralized NFS storage for all Production/DR VMs
Users:   root, admin, veeam_emergency
Note:    Handles memory/CPU pressure during concurrent Veeam backups
```

### vCenter Server Appliance
```
Memory:  7GB (reduced from 8GB after disabling unnecessary services)
CPU:     3 vCPU
Disk:    Tiny deployment (~500GB)
Network: 2 vNIC (WAN + LAN)
IP:      10.0.20.89 (LAN), 192.x.x.## (WAN)
Purpose: Cluster orchestration & management
Disabled Services:
  ├─ Hybrid vCenter Service
  ├─ Workload Control Plane
  └─ VMware Observability Vapi Service
```

### Veeam Backup & Replication
```
Memory:  5GB (increased from 4GB to eliminate latency during operations)
CPU:     3 vCPU
Disk:    80GB OS + 600GB repository
Network: 1 vNIC (Internal)
IP:      10.0.20.195
FQDN:    veeam.home.lab
OS:      Windows Server 2022
Purpose: VM backup & disaster recovery
Users:   Administrator
Note:    Stable at 5GB when only Veeam is running (no other heavy apps)
```

### pfSense Firewall
```
Memory:  2GB
CPU:     2 vCPU
Disk:    40GB OS
Network: 2 vNIC (WAN + LAN)
IP:      192.x.x.## (WAN), 10.0.20.170 (LAN)
FQDN:    pfsense.home.lab
OS:      FreeBSD (pfSense)
Purpose: Network gateway, firewall, DNS backup
Users:   root, veeam_emergency
```

### IPA Server - Identity Management
```
Memory:  2GB
CPU:     2 vCPU
Disk:    30GB OS + 2×20GB RAID1
Network: 1 vNIC
IP:      10.0.20.184
FQDN:    ipa.home.lab
OS:      Rocky Linux 10
Purpose: Kerberos, LDAP, DNS, NTP, SSO for entire domain
Users:   root, admin, veeam_emergency
Domain:  admin, super_ansible
Note:    Primary identity provider for home.lab domain
```

---

## Production VMs (ESXi Nested Production)

### Vault Cluster - Secrets Management
```
Vault-1: 1.75GB RAM, 2 vCPU, 20GB OS + 2×5GB RAID1, IP: 10.0.20.191, vault-01.home.lab
Vault-2: 1.75GB RAM, 2 vCPU, 20GB OS + 2×5GB RAID1, IP: 10.0.20.192, vault-02.home.lab
Vault-3: 1.75GB RAM, 2 vCPU, 20GB OS + 2×5GB RAID1, IP: 10.0.20.193, vault-03.home.lab
OS:      Rocky Linux 10
Purpose: Distributed secrets management (Raft consensus)
Users:   root, veeam_emergency
Domain:  vault_admin1, vault_admin2/3/4, super_ansible
```

### Kubernetes Cluster
```
K8s-Master:   3GB RAM, 3 vCPU, 90GB OS + 2×60GB RAID1, IP: 10.0.20.181, k8s-master.home.lab
K8s-Worker-1: 2.25GB RAM, 2 vCPU, 50GB OS + 2×30GB RAID1, IP: 10.0.20.182, k8s-worker1.home.lab
K8s-Worker-2: 2.25GB RAM, 2 vCPU, 50GB OS + 2×30GB RAID1, IP: 10.0.20.183, k8s-worker2.home.lab
K8s-Worker-3: 2.25GB RAM, 2 vCPU, 50GB OS + 2×30GB RAID1, IP: 10.0.20.187, k8s-worker3.home.lab
OS:      Rocky Linux 10
Purpose: Container orchestration platform
Users:   root, veeam_emergency
Domain:  admin1, admin2, super_ansible
Note:    RAID1 for data persistence and redundancy
```

### Monitoring - Prometheus & Grafana
```
Memory:  2GB (may need +1GB for time-series DB growth)
CPU:     3 vCPU # changed from 2 VCPU as noted after setup and start, it need a bit more
Disk:    90GB OS + 2×20GB RAID1
IP:      10.0.20.186
FQDN:    monitor.home.lab
OS:      Rocky Linux 10
Purpose: Metrics collection (Prometheus) and visualization (Grafana)
Users:   root, veeam_emergency
Domain:  super_ansible
Note:    RAID1 for metrics history protection
```

### Ansible - Automation Controller
```
Memory:  2.5GB
CPU:     3 vCPU (high CPU for parallel playbook execution)
Disk:    90GB OS + 2×60GB RAID1
IP:      10.0.20.185
FQDN:    ansible.home.lab
OS:      Rocky Linux 10
Purpose: Infrastructure automation & orchestration
Users:   root, veeam_emergency
Domain:  ansible_admin, super_ansible
Note:    Larger RAID1 for playbook repository and logs
```

### Jenkins Master - CI/CD
```
Memory:  3GB
CPU:     3 vCPU
Disk:    90GB OS + 2×20GB RAID1
IP:      10.0.20.196
FQDN:    jenkins-master.home.lab
OS:      Rocky Linux 10
Purpose: Continuous integration & delivery pipelines
Users:   root, veeam_emergency
Domain:  super_ansible
Note:    RAID1 for build artifacts protection
```

---

## DR Configuration (Cold Standby)

### ESXi DR Server
```
Status:  POWERED OFF (0GB memory consumption)
Purpose: Manual disaster recovery failover
RTO:     15-20 minutes activation time
Config:  Mirror of Production ESXi (same resource allocation)
VMs:     IPA Replica + shadow copies of critical workloads
```

---

## Key Architectural Decisions

### Decision 1: Cold Standby DR vs Active HA

**Original Plan:**
- 2 Active ESXi Hosts (22GB each = 44GB total)
- Automatic failover with DRS and HA
- Each nested ESXi: 22GB allocated

**Problem Discovered:**
ESXi memory ballooning behavior in nested environments:
- ESXi reserves 3GB on boot (even if VMs use less)
- When VMs migrate, old host DOESN'T release memory
- Example:
  - Production ESXi boots: 3GB reserved
  - Start 5 VMs: 15GB allocated (total 18GB)
  - Migrate 3 VMs to DR: DR now uses 12GB
  - Production STILL holds 18GB (doesn't release!)
  - Total: 18GB + 12GB = 30GB (memory exhaustion!)

**Solution: Cold Standby DR**
- DR ESXi powered OFF = 0GB consumption
- Production gets full 27GB allocation
- Manual failover acceptable for lab environment
- Saved memory reallocated to Production VMs and Infrastructure

**Trade-offs:**
- ❌ Lost: Automatic HA failover
- ❌ Lost: Live migration between hosts
- ✅ Gained: 27GB for Production + 25GB for Infrastructure (vs 22GB each with active HA)
- ✅ Gained: 3 K8s workers instead of 2 (true application HA)
- ✅ Gained: IPA moved to Infrastructure layer for better resource distribution

---

### Decision 2: Dedicated VMs for Vault & Jenkins

**Original Plan:**
- Run as containers on Ansible VM
- Vault: 3 containers
- Jenkins: 1 container
- Benefit: Lower memory footprint (Ansible VM: 5GB total)

**Why Switched to Dedicated VMs:**
- ✅ Dependency isolation: Core services shouldn't depend on containers
- ✅ Security: Vault needs isolated environment (handles secrets)
- ✅ Reliability: Separate failure domains
- ✅ Learning: Simulates real-world enterprise architecture
- ✅ Future-proof: Easier to scale independently

**Memory Impact:**
- Before: Ansible 5GB (hosting containers)
- After: Ansible 2GB + Vault 6GB + Jenkins 3GB = 11GB
- Trade-off accepted: Better architecture > memory savings

---

### Decision 3: Thick Provisioning for NAS VM

**Rationale:**
- ✅ Predictable performance (no thin provisioning overhead)
- ✅ Guaranteed space for critical NFS storage
- ✅ Simpler snapshot management (dedicated datastore)
- ⚠️ Requires 2x disk space for snapshots

**Snapshot Sizing Rule:**
For thick provisioned disks, datastore must have ≥ 2× disk size:
- NAS VM: 905GB thick data disks (900GB + 5GB)
- Snapshot requirement: ~905GB × 1.5 = ~1358GB
- Requires: DS_NVME_2 ≥ 2TB
- Solution: Dedicated 2TB datastore for NAS only

**Reference:** See troubleshooting case [09-Thick-Provisioned-Snapshot-Size.txt](../../../05-TROUBLESHOOTING/cases/storage/09-Thick-Provisioned-Snapshot-Size.txt)

---

### Decision 4: Three Kubernetes Workers

**Kubernetes HA Requirements:**
- Need N/2+1 for quorum
- Minimum 3 workers for true HA
- Allows 1 worker failure + 2 healthy nodes remain

**Without Cold Standby DR:**
- Only 22GB available for Production (with old resource allocation)
- Could only fit 2 workers
- No real HA at application layer

**With Cold Standby DR:**
- 27GB available for Production ESXi
- Can fit 3 workers (3×2.5GB = 7.5GB)
- True application-layer HA achieved
- Workload survives single node failure
- IPA moved to Infrastructure for better isolation

---

## VM Resource Summary

### Infrastructure Layer Total
```
NAS:       9GB RAM, 4 vCPU
vCenter:   7GB RAM, 3 vCPU
Veeam:     5GB RAM, 3 vCPU
IPA:       2GB RAM, 2 vCPU
pfSense:   2GB RAM, 2 vCPU
────────────────────────────
Total:    25GB RAM, 14 vCPU
```

### Production Layer Total
```
Vault (3×2GB): 6GB RAM, 6 vCPU (3×2)
K8s Master:    3GB RAM, 3 vCPU
K8s Workers:   7.5GB RAM, 6 vCPU (3×2.5GB)
Grafana:       2GB RAM, 3 vCPU
Ansible:       2GB RAM, 3 vCPU
Jenkins:       3GB RAM, 3 vCPU
────────────────────────────
Total:        23.5GB RAM, 24 vCPU
+ ESXi Overhead: 3.5GB
────────────────────────────
Grand Total:  27GB RAM, 25 vCPU (10 allocated to nested ESXi)
```

---

## Future Capacity Considerations

### Potential Adjustments
- **Grafana**: May need +1GB (currently 2GB, tight for time-series DB)
- **Jenkins**: May need +1GB if heavy pipeline parallelism required
- **K8s Workers**: May add 4th worker if DR is permanently activated

### Capacity Headroom
- Current buffer: Minimal (~1-2GB)
- If DR activated: Would consume 27GB (requires Production shutdown first)
- Maximum safe allocation: 63GB (leaving 1GB buffer minimum)

---

## Related Documentation

- [Resource Overview](01-Resource-Overview.md)
- [Best Practices and Optimization](03-Best-Practices-and-Optimization.md)
- [Storage Architecture](../Storage/)
- [Network Architecture](../Network/)
