# Resource Allocation Overview

> **How 64GB RAM and 16 vCPU power a complete enterprise infrastructure**

---

## Overview

This document explains the resource allocation strategy for the entire DC-K8s environment, including memory distribution, CPU over-commitment, and storage planning.

**Total Available:**
- **Memory**: 64GB Physical RAM
- **CPU**: 16 vCPU @ 3.1GHz+
- **Storage**: 4.5TB across 3 NVMe drives

---

## Memory Allocation Hierarchy

### Total Available: 64GB Physical RAM

```
64GB Physical RAM
│
├─ [11GB] ──── Windows 11 Host
│              └─ Reserved for OS stability (prevents swap usage)
│
└─ [53GB] ─── ESXi Master VM
    │
    ├─ [24GB] ─ Infrastructure Layer (Always Running)
    │   ├─ [8GB]  NAS (Storage Server)
    │   ├─ [7GB]  vCenter (Orchestration)
    │   ├─ [5GB]  Veeam (Backup & Recovery)
    │   ├─ [2GB]  IPA (Identity Management)
    │   └─ [2GB]  pfSense (Network Gateway)
    │
    │
    ├─ [25.5GB] ─ Production ESXi (ACTIVE)
    │   │
    │   ├─ [22.5GB] Production VMs (Running)
    │   │   ├─ [5.25GB]   Vault Cluster (3×1.75GB)
    │   │   ├─ [3GB]   K8s-Master
    │   │   ├─ [6.75GB] K8s-Workers (3×2.25GB)
    │   │   ├─ [2GB]   Grafana (Monitoring)
    │   │   ├─ [2.5GB]   Ansible (Automation)
    │   │   └─ [2.75GB]   Jenkins (CI/CD)
    │   │
    │   └─ [3GB] ESXi Overhead
    │       └─ Management processes & buffers
    │
    ├─ [0GB] ─ DR ESXi (COLD STANDBY - POWERED OFF)
    │   │
    │   │      Status: Disconnected from vCenter but existing in same cluster as Production ESXI
    │   │      Memory Usage: 0GB (VM powered off)
    │   │      Purpose: Manual disaster recovery
    │   │      Activation: 15-20 min RTO
    │   │      Weekly Updated within maintaince window to be sync same config as Prod
    │   │
    │   └─ [25.5GB when activated]
    │       └─ Mirror of Production environment
    │
    └─ [3GB] ─ ESXi Master Overhead
        └─ Virtualization management layer
```

### Memory Allocation Summary

| Component | Allocated | Purpose |
|-----------|-----------|---------|
| Windows Host | 11GB | Host OS stability |
| ESXi Master Overhead | 3GB | Hypervisor management |
| Infrastructure VMs | 24GB | Core services (vCenter, NAS, Veeam, pfSense) |
| Production ESXi + VMs | 25.5GB | Active workload environment |
| DR ESXi | 0GB | Powered off (cold standby) |
| **Total** | **64GB** | **90-95% utilized when Production active** |

---

## CPU Allocation Strategy

### Physical CPU: 16 vCPU @ 3.1GHz+

#### Layer 2 - ESXi Master Level
```
Physical CPU: 16 vCPU
│
├─ ESXi Master: 16 vCPU allocated
│   ├─ Infrastructure VMs: 13 vCPU
│   │   ├─ vCenter: 3 vCPU
│   │   ├─ Veeam: 3 vCPU
│   │   ├─ NAS: 4 vCPU
│   │   ├─ IPA: 2 vCPU
│   │   └─ pfSense: 2 vCPU
│   │
│   └─ Production ESXi: 10 vCPU
│
└─ Over-commitment: 24/16 = 150% (OK Zone)
```

**Why This Works:**
- ✅ High-frequency CPU (3.1GHz+) handles over-commitment efficiently
- ✅ Most VMs idle or <40% utilization during normal operations
- ✅ Measured host CPU usage: ~30% average, 40-45% during backups
- ✅ ESXi scheduler intelligently distributes CPU cycles
- ✅ Workloads are complementary (not all peak simultaneously)

#### Layer 3 - Production ESXi Level
```
Production ESXi: 10 vCPU allocated
│
├─ K8s Master: 3 vCPU
├─ K8s Worker-1: 2 vCPU
├─ K8s Worker-2: 2 vCPU
├─ K8s Worker-3: 2 vCPU
├─ Ansible: 3 vCPU
├─ Jenkins Master: 3 vCPU
├─ Grafana: 4 vCPU
├─ Vault-1: 2 vCPU
├─ Vault-2: 2 vCPU
└─ Vault-3: 2 vCPU

Total: 24 vCPU
Over-commitment: 24/10 = 240%
```

**Safe Because:**
- ✅ Vault: Low CPU usage (mostly idle)
- ✅ K8s workloads: Moderate, bursty (not sustained)
- ✅ Ansible: High during playbook runs, idle otherwise
- ✅ Testing confirmed stable operation under realistic load

---

## Storage Allocation

### Physical Storage: 3 NVMe Drives (Total: 4.5TB)

```
NVME0: 2TB
└─ Windows 11 OS + Personal Data

NVME1: 2TB (Primary Virtual Disk Storage)
└─ VMware Workstation Virtual Disks
    ├─ ESXi Master OS: 150GB (Thin)
    │
    ├─ vDisk: DS_NVME_1 (2TB Thin)
    │   └─ Datastore: DS_NVME_1
    │       ├─ pfSense VM
    │       ├─ vCenter VM
    │       ├─ IPA VM
    │       ├─ Veeam VM (80GB OS + 600GB repository)
    │       ├─ ESXi Production VM (150GB)
    │       ├─ ESXi DR VM (150GB)
    │       ├─ ISO Folder
    │       └─ VM Templates
    │
    └─ vDisk: DS_NVME_2 (2TB Thin)
        └─ Datastore: DS_NVME_2 (Dedicated for NAS)
            └─ NAS VM: 940GB (Thick Provisioned)
                ├─ OS: 30GB
                └─ Data: 900GB
                    ├─ NFS Share 1: 900GB (Production VMs)
                    └─ NFS Share 2: 10GB (HA Heartbeat && Shared Storage for vCenter backup && ETCD)

NVME2: 500GB (External - DR)
└─ Offsite Backup Repository
    └─ Veeam backup copy jobs
```

### Storage Strategy by VM Type

| VM Type | Provisioning | Rationale |
|---------|--------------|-----------|
| **NAS VM** | Thick | Predictable performance, guaranteed space for NFS |
| **All Other VMs** | Thin | Flexibility, efficient space usage |
| **vCenter** | Thin | Moderate growth, snapshots needed |
| **Veeam** | Thin | Variable backup size |

### Datastore Capacity Planning

**DS_NVME_1** (Infrastructure):
- Capacity: ~2TB
- Usage: ~1.5TB allocated (thin)
- Headroom: 500GB available
- Safe for snapshots: ✓ (all thin provisioned)

**DS_NVME_2** (NAS Dedicated):
- Capacity: 2TB
- Usage: 940GB (30GB OS thin + 910GB thick data disks)
- Rule: 2x disk size for snapshot safety (thick disks only)
- Calculation: 2TB > 2×940GB ✓ (sufficient space)

**NAS_DS_1** (NFS from NAS VM):
- Capacity: 900GB
- Allocated: ~780GB (Production VMs)
- Actual Usage: ~400-500GB (thin provisioning)
- Headroom: 120GB
- Over-provisioning: Safe with thin VMs

---

## Capacity Summary

**Memory Utilization:**
- Total Physical: 64GB
- Allocated: 61GB
- Available Buffer: 3GB
- DR Activation: Requires Production shutdown first

**CPU Utilization:**
- Physical: 16 vCPU @ 3.1GHz+
- Layer 2 Over-commitment: 194% (31 vCPU / 16)
- Layer 3 Over-commitment: 230% (23 vCPU / 10)
- Measured Usage: ~30% average, 35-40% peak

**Storage Utilization:**
- Total Physical: 4.5TB
- Allocated (thin): ~4.2TB (2.3x over-provisioned)
- Actual Usage: ~1.8TB (40%)
- External DR: 500GB (offsite backup)

---

## Disaster Recovery Capacity Planning

### Normal Operations
```
Production ESXi: ACTIVE (25.5GB)
DR ESXi: POWERED OFF (0GB)
Available: 53GB - 24GB infra - 25.5GB production - 3GB overhead = 0.5GB free
```

### DR Activation Process
1. **Production ESXi failure detected**
2. **Shutdown Production ESXi** (frees 25.5GB) 
3. **Power on DR ESXi** (consumes 25.5GB)
4. **Connect DR ESXi to vCenter cluster**
5. **Migrate All VMs to DR Server** ** Run script to do full migration to DR Server. "if the the prod down, will be able to do the migration ? i know the storage resources is on NAS and compuite resources can be changed and no dependancy on vapp so mostly yes in shaa allah.
6. The script also will run DR Server first , its sequence of signal to be triggered to Vcneter , since vcneter manage the esxi also, then it can reach the DR Server Node, so we may ,
   Script to shutdown production server while starting up DR Server ,
   Script to make sure the DR Server exist in cluster and connected
   Script to perform migration to all vms while they offline to DR
   Script to configure the DR Server for same auto satrt config
   Script to start Prod Server in maintance mode and send email with incident at beginig and at the end  

This is a very smart workflow, Sabry. You are asking the exact right question: "Can I migrate if the source is dead?"
The short answer is: No, you cannot use a standard "Migrate" command if the Production ESXi is down.
However, because you are using NAS (Shared Storage), you CAN recover them. You just need to change the word (and the command) you use.
Here is the Engineering correction to your flow to make it 100% fail-safe.
1. The "Migration" Trap
In VMware, a "Migration" (vMotion or Cold Migration) requires the Source Host to be alive to "hand over" the VM to the Destination Host.
If Production ESXi is OFF, the vCenter Agent on that host is dead.
vCenter will show the VMs as "Disconnected" or "Inaccessible."
If you try to run Move-VM script, it will fail because vCenter cannot talk to the old host to release the lock.
2. The Solution: "Unregister & Register"
Since your data (VMDK and VMX files) lives on the NAS, the data is safe. The DR Host just needs to be told where they are.
Your script logic should change from "Migrate" to "Register".
The Corrected Flow (Point 6 Revised):
Kill Switch: Script sends hard shutdown command to Production ESXi (IPMI or forceful SSH). Goal: Ensure no file locks on the NAS.
Wake Up: Script sends Wake-on-LAN (WoL) to DR ESXi.
Wait Loop: Script pings DR ESXi until it responds, then waits for vCenter to reconnect the host.
The "Migration" Alternative (The Magic Step):
Action: The script scans the NAS Datastore.
Action: It finds all .vmx files.
Action: It runs the Register-VM command to add these VMs to the DR ESXi inventory.
Note: If vCenter still thinks the VMs are on the dead host, the script first forces them to be "Removed from Inventory" (not deleted from disk).
Power On: Script starts the VMs in the correct priority order (DNS/Vault first, then Apps).
Notification: Script sends the "DR Activated" email.


Second Scenario: Maintaince planned not Full DR , 
We will then need to do live migration, so we will trigger DR server to start , then trigger the migration live via vmotion , there already one dedicated vswitch there for vmotion service configured and tested 
, then trigger the auto start config order 
, then put Prod in maintaince mode "" But will need to make sure to fix the memory balloning in prod server after each VM migrate done , because if we didnt do , the main big server will not hold on because bother Prod and DR will require the mem , so double the mem expected
There is a critical engineering difference between the two, and understanding it is the key to why your plan will work (and why Hot Remove would fail).1. Why it is NOT "Hot Remove"Hot Remove means physically ripping a RAM stick out of the VM while it is running.The Problem: ESXi (the Operating System running inside your nested VM) does not support Hot Remove of memory. If you try to change the VM settings from 26GB to 24GB while it is powered on, the operation will fail or is disabled.Result: You cannot use Hot Remove to shrink the production server.2. What we are using: "Ballooning" (The Fake Out)We are using the Resource Limit (MemLimitMB), which is a "Software constraint," not a "Hardware change."The Hardware View: The Nested ESXi still thinks it has 26GB of RAM installed. It sees 26GB in its Task Manager.The Trick: When you lower the Limit to 24GB on the Master, the Master tells the VMware Tools inside the Nested ESXi:"Hey, inflate a balloon of dummy data to 2GB size."The Result: The Nested ESXi marks 2GB as "Used by Driver." It doesn't know that the Master has actually taken those physical RAM chips away and given them to the DR server.Summary of the DifferenceFeatureActionSupported by Nested ESXi?What happens?Hot Remove"Remove Hardware"NOError / Operation Not Allowed.Limit Squeeze"Constrain Resources"YESThe Balloon Driver inflates. The VM keeps running, but uses less physical RAM.Why this matters for your ScriptYour script must use the command to Set Resource Configuration (Limit), NOT the command to Set-VM (Memory Size).Correct Command (Ballooning):PowerShellGet-VM "Prod-ESXi" | Get-VMResourceConfiguration | Set-VMResourceConfiguration -MemLimitMB 24000
Incorrect Command (Hot Remove):PowerShellSet-VM "Prod-ESXi" -MemoryGB 24  <-- THIS WILL FAIL
You are effectively "starving" the Production server of physical pages, forcing it to be efficient, rather than removing its capacity. This is why the VMware Tools service is mandatory inside the nested VM—it is the one inflating the balloon.



**Recovery Metrics:**
- **RTO** (Recovery Time Objective): 15-20 minutes
- **RPO** (Recovery Point Objective): Last backup/snapshot

---

## Resource Allocation Principles

**Memory:**
- 9GB reserved for Windows host (prevents swap)
- Cold standby DR (0GB when off, 25.5GB when active)
- 100% allocation acceptable with planning

**CPU:**
- Over-commitment safe up to 250% with complementary workloads
- Monitor host CPU usage regularly
- High-frequency CPU essential for good performance

**Storage:**
- Thick provisioning for NAS (predictable performance)
- Thin provisioning for all other VMs (efficiency)
- 2.3x over-provisioning safe with monitoring
- Dedicated datastore for thick-provisioned VMs

---

## Related Documentation

- [VM Specifications and Decisions](02-VM-Specifications-and-Decisions.md)
- [Best Practices and Optimization](03-Best-Practices-and-Optimization.md)
- [Storage Architecture](../Storage/)
- [Network Architecture](../Network/)
