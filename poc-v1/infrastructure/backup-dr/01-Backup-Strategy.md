================================================================================
BACKUP STRATEGY
Disaster Recovery Guide - Part 1
================================================================================
Last Updated: 2026-01-03
Back to: [README.md](README.md)

================================================================================
TABLE OF CONTENTS
================================================================================
1. Dual Veeam Architecture
2. Backup Repository Strategy
3. vCenter Built-in Backup
4. Backup Performance Optimization
5. Backup Notification

================================================================================
1. DUAL VEEAM ARCHITECTURE
================================================================================

## Why Two Veeam Servers?

- Veeam Community Edition: Limited to 10 VMs per instance
- Outer Veeam: Backs up inner layer VMs (application layer)
- Inner Veeam: Backs up outer layer infrastructure VMs

Total VMs: 17 (10 inner layer + 7 outer layer) = Requires 2 instances

## Outer Veeam (Host Level - Windows Server)

**Location:** Windows Host (192.168.0.x)
**Targets:** Inner layer application VMs
**Repository:** Default Backup Repository (Host storage: D:\Veeam_Backups\)
**Connection Method:** vCenter on Production ESXi (10.0.20.101)

**Backup Jobs:**
1. **Vault Cluster** - 3 VMs - Scheduled: 8:20 PM daily
2. **K8s Workers** - 3 VMs - Scheduled: 8:45 PM daily
3. **K8s Master** - 1 VM - Scheduled: 9:35 PM daily
4. **Automation VMs** - 2 VMs (Ansible, Jenkins) - Scheduled: 9:10 PM daily
5. **Monitor** - 1 VM - Scheduled: 9:50 PM daily

**Total:** 10 VMs (at Veeam Community Edition limit)

**Connection Architecture:**
```
Outer Veeam (Windows Host)
    ↓
vCenter (10.0.20.89)
    ↓
Production ESXi (10.0.20.101)
    ↓
├─ Vault-01, Vault-02, Vault-03
├─ K8s-Master
├─ K8s-Worker-1, K8s-Worker-2, K8s-Worker-3
├─ Ansible
├─ Jenkins
└─ Monitor
```

## Inner Veeam (Inner Layer - 10.0.20.195)

**Location:** Windows Server 2022 VM on ESXi Master
**Targets:** Outer layer infrastructure VMs
**Repository:** Backup Repository Host (NAS storage: /mnt/backups/veeam/)
**Connection Method:** Standalone ESXi Master (10.0.20.100) - Direct connection

**Why Standalone ESXi?** See [06-Design-Decisions.md](06-Design-Decisions.md#why-standalone-esxi-for-outer-layer-backups)

**Backup Jobs:**
1. **IPA** - 1 VM - Scheduled: 10:30 PM daily
2. **pfSense** - 1 VM - Scheduled: 7:50 PM daily
3. **NAS Server** - 1 VM - Manual (during maintenance window)
4. **Production ESXi** - 1 VM - Manual (during shutdown window)
5. **DR ESXi** - 1 VM - Manual (during shutdown window)
6. **vCenter** - 1 VM - Manual (during maintenance window)
7. **Veeam (Inner)** - 1 VM - Scheduled: 11:15 PM daily

**Automated:** 3 VMs daily
**Manual:** 4 VMs (scheduled maintenance windows)

**Connection Architecture:**
```
Inner Veeam (10.0.20.195)
    ↓
ESXi Master (10.0.20.100) [Standalone Direct - NOT vCenter]
    ↓
├─ IPA
├─ pfSense
├─ NAS
├─ Production ESXi (nested)
├─ DR ESXi (nested)
├─ vCenter ← NOTE: Backed up via ESXi, not through itself
└─ Veeam (Inner)
```

================================================================================
2. BACKUP REPOSITORY STRATEGY
================================================================================

## Inner Veeam Backup Storage

**Primary Repository:** NAS Storage (NFS mount)
- Path: /mnt/backups/veeam/ (or similar NAS location)
- Contains: All outer layer VM backups (IPA, pfSense, NAS, ESXi hosts, vCenter, Inner Veeam)

**Secondary Repository (Optional - Not Currently Used):** Windows Host Storage (SMB)
- Name: Backup Repository - Host
- Type: SMB share
- Path: \\10.0.20.1\Backup
- Capacity: ~471.6 GB
- Gateway: pfSense (auto-selected for SMB routing)
- Status: Configured but idle (available for future use)
- Purpose: Provides flexibility to store select backups on Windows Host if needed
- Note: NOT used for backup copy jobs (see [06-Design-Decisions.md](06-Design-Decisions.md#why-no-backup-copy-jobs))

## Cross-Layer Backup Protection

**Inner Veeam VM Backup (by Outer Veeam):**
- Outer Veeam backs up the Inner Veeam VM itself (all disks: OS + Data)
- Inner Veeam VM disks contain:
  - Veeam software installation
  - Veeam configuration database
  - Backup job metadata and history
  - Local Veeam cache and temporary files

**What This Protects:**
- Veeam configuration and job definitions
- Backup metadata (what was backed up, when, restore points)
- Ability to rebuild Inner Veeam server with all job configurations intact

**What This Does NOT Protect:**
- Actual backup files on NAS (those remain only on NAS repository)
- If NAS fails, outer layer backup data is lost regardless

**Why No Backup Copy Jobs?**
See [06-Design-Decisions.md](06-Design-Decisions.md#why-no-backup-copy-jobs) for full explanation.
- Summary: Rejected due to complexity, performance overhead, and limited benefit for lab environment

================================================================================
3. VCENTER BUILT-IN BACKUP
================================================================================

**Location:** vCenter Server (10.0.20.89)
**Target:** NAS Storage /mnt/datastor2
**Backup Size:** 10 GB (estimated)
**Retention:** Maximum 4 backups

## Rationale

- vCenter has two disks: 30 GB OS disk + 10 GB data disk
- etcd cluster state and vCenter configuration stored on 10 GB data disk
- Veeam backup excludes the larger 900 GB disk partition
- Veeam captures full VM (30 GB OS + 10 GB data = 40 GB total)
- vCenter built-in backup provides application-aware point-in-time recovery
- Stored on /mnt/datastor2 instead of /mnt/shared_storage for separation

## Configuration

- Backup Protocol: FTPS, HTTPS, SFTP, FTP, NFS, or SMB
- Schedule: Manual or automated (configure via vCenter UI)
- Encryption: Enabled (password-protected backup files)
- Retention Policy: Keep maximum 4 backups (auto-delete oldest)

**Access:** vCenter UI > Menu > Administration > Deployment > System Configuration > Backup

## Important Notes

- vCenter backup includes database, configuration, certificates, and inventory
- Use this for vCenter recovery; use Veeam for full VM disaster recovery
- Both backups complement each other (application-aware vs. VM-level)
- 4 backup retention provides 4 recovery points while limiting storage usage

================================================================================
4. BACKUP PERFORMANCE OPTIMIZATION
================================================================================

## Storage Access Method

**Chosen:** Direct Storage Access (via VMware APIs)
**Alternative Rejected:** Network Mode (NBD)

**Performance Testing Results:**
- Direct Storage: Safe for environment I/O, no congestion detected
- Network Mode: Adds load, unpredictable completion times
- Monitoring: Tested on both NAS storage and VM levels

## Concurrency Configuration

**Setting:** 1 concurrent task maximum

**Rationale:**
- Prevents I/O contention on NAS storage
- Ensures predictable backup windows
- Avoids job queue collisions during DR scenarios

## Network Throttling

**Configured (if fallback enabled):**
- Speed Limit: 200 MB/s
- Prevents network saturation during backup windows

**Current Configuration:**
- Network Mode: DISABLED as fallback
- Reason: Unpredictable completion times could cause job overlap
- Impact: If Direct Storage fails, backup fails (no silent fallback)

## Timing Strategy

**Schedule Design:**
- Each job has 10-minute buffer before next job starts
- Buffer based on real-world performance testing
- Purpose: Prevent job queue collisions during emergency shutdown

**Example Timeline:**
- 7:50 PM: pfSense backup (20 min estimated)
- 8:20 PM: Vault Cluster backup (25 min estimated)
- 8:45 PM: K8s Workers backup (30 min estimated)

**Emergency Shutdown Consideration:**
During DR event:
- Running job: Killed immediately (hard stop)
- Queued jobs: Won't start due to timing buffers
- Prevents: Multiple jobs in queue waiting for shutdown

See [03-Emergency-Shutdown.md](03-Emergency-Shutdown.md) for shutdown details.

================================================================================
5. BACKUP NOTIFICATION
================================================================================

**Email Setup:**
- Gmail account created for Veeam
- Reports sent to personal email
- Includes: Job status, output, errors
- Purpose: Monitoring without logging into Veeam

**Configuration:**
- Both Outer and Inner Veeam send email notifications
- Success and failure alerts configured
- Daily summary emails for scheduled jobs

================================================================================
RELATED DOCUMENTATION
================================================================================

- [02-User-Accounts.md](../Identity/02-User-Accounts.md) - Authentication for backup operations
- [05-Recovery-Procedures.md](05-Recovery-Procedures.md) - How to restore from backups
- [06-Design-Decisions.md](06-Design-Decisions.md) - Why these architectural choices?
- [07-Configuration-Reference.md](07-Configuration-Reference.md) - Repository paths and settings
- [VM Startup-Shutdown](../../01-Infrastructure-Layer/DR/04-VM-Startup-Shutdown.md) - ESXi auto-startup configuration
- [DR Failover Procedures](../../01-Infrastructure-Layer/DR/08-DR-Failover-Procedures.md) - Infrastructure failover

Back to: [README.md](README.md)
