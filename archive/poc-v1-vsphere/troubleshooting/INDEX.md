# Troubleshooting Index

34 real incident cases documented during POC v1 (VMware vSphere) development.

---

## Categories

| Folder | Tickets | Range | Description |
|--------|---------|-------|-------------|
| [platform/](platform/) | 16 | 1-16 | vCenter, ESXi, Windows host, FreeIPA |
| [storage/](storage/) | 10 | 1-10 | Snapshots, NAS, VMDK, backup |
| [network/](network/) | 5 | 1-5 | pfSense, loops, routing |
| [application/](application/) | 3 | 1-3 | Prometheus, Jenkins, Git |

---

**Total: 34 troubleshooting tickets across 4 categories**

---

## Platform (16 cases)

| # | Issue | Key Learning |
|---|-------|--------------|
| 1 | [vCenter Installation Stage2 Hang](platform/1-vCenter-Installation-Stage2-Hang.md) | DNS resolution required for FQDN |
| 2 | [vCenter Authentication Error SSO](platform/2-vCenter-Authentication-Error-SSO.md) | SSO configuration issues |
| 3 | [vCenter Lifecycle Manager Depot Error](platform/3-vCenter-Lifecycle-Manager-Depot-Error.md) | Depot connectivity |
| 4 | [vCenter Certificate Browser Error](platform/4-vCenter-Certificate-Browser-Error.md) | Browser trust issues |
| 5 | [vCenter Certificate Manager Replace Failed](platform/5-vCenter-Certificate-Manager-Replace-Failed.md) | Certificate replacement process |
| 6 | [vCenter API SSL Error After Root CA](platform/6-vCenter-API-SSL-Error-After-Root-CA.md) | SSL chain validation |
| 7 | [Windows Host Sleep Network Break](platform/7-Windows-Host-Sleep-Network-Break.md) | Sleep mode breaks nested VMs |
| 8 | [Windows Host NAT vs Bridge](platform/8-Windows-Host-NAT-vs-Bridge.md) | Network mode decision |
| 9 | [vCenter8 vApp Config Not Persisting](platform/9-vCenter8-vApp-Config-Not-Persisting.md) | vApp configuration gotchas |
| 10 | [FreeIPA Time Sync Clock Skew](platform/10-FreeIPA-Time-Sync-Clock-Skew.md) | Kerberos time requirements |
| 11 | [FreeIPA SSSD Cache Not Updating](platform/11-FreeIPA-SSSD-Cache-Not-Updating.md) | SSSD cache invalidation |
| 12 | [vCenter Backup Failure After IP Change](platform/12-vCenter-Backup-Failure-After-IP-Change.md) | IP change impacts |
| 13 | [vSphere Lifecycle Manager Plugin Download Error](platform/13-vSphere-Lifecycle-Manager-Plugin-Download-Error.md) | Plugin download issues |
| 14 | [vCenter Firewall Invalid Interface Error](platform/14-vCenter-Firewall-Invalid-Interface-Error.md) | Firewall configuration |
| 15 | [ESXi Master AutoProtect Snapshot Performance](platform/15-ESXi-Master-AutoProtect-Snapshot-Performance-Degradation.md) | Snapshot performance impact |
| 16 | [VMware Workstation Hyper-V Conflict](platform/16-vmwareworkstation-hyperv-conflict.md) | Hypervisor conflicts |

## Storage (10 cases)

| # | Issue | Key Learning |
|---|-------|--------------|
| 1 | [VMDK Snapshot Corruption](storage/1-vmdk-snapshot-corruption.md) | Snapshot chain integrity |
| 2 | [NAS Snapshot Sizing Failure](storage/2-nas-snapshot-sizing-failure.md) | Snapshot space planning |
| 3 | [Disk Race Condition Disaster](storage/3-disk-race-condition-disaster.md) | Concurrent disk access |
| 4 | [Thick to Thin Conversion](storage/4-thick-to-thin-conversion.md) | Disk format conversion |
| 5 | [NAS Memory Starvation](storage/5-nas-memory-starvation.md) | NAS resource limits |
| 6 | [NAS Backup Strategy Optimization](storage/6-NAS-Backup-Strategy-Optimization.md) | Backup optimization |
| 7 | [VMware Snapshot Chain Corruption](storage/7-VMware-Snapshot-Chain-Corruption.md) | Chain repair |
| 8 | [Thick Provisioned Snapshot Size](storage/8-Thick-Provisioned-Snapshot-Size.md) | Thick disk snapshot behavior |
| 9 | [Application Aware Backup Loop Device Errors](storage/9-Application-Aware-Backup-Loop-Device-Errors.md) | App-aware backup issues |
| 10 | [Snapshot Chain Corruption Sleep Mode](storage/10-Snapshot-Chain-Corruption-Sleep-Mode.md) | Sleep mode corruption |

## Network (5 cases)

| # | Issue | Key Learning |
|---|-------|--------------|
| 1 | [Promiscuous Mode Nested](network/1-promiscuous-mode-nested.md) | Nested VM networking |
| 2 | [Duplicate Packets Loop](network/2-duplicate-packets-loop.md) | Network loop detection |
| 3 | [pfSense Poweroff](network/3-pfsense-poweroff.md) | pfSense shutdown handling |
| 4 | [Windows Host Network Loops](network/4-Windows-Host-Network-Loops.md) | Host network configuration |
| 5 | [Static Route Loop SSH Disconnect](network/5-Static-Route-Loop-SSH-Disconnect.md) | Routing table issues |

## Application (3 cases)

| # | Issue | Key Learning |
|---|-------|--------------|
| 1 | [Prometheus Setup Issues](application/1-Prometheus-Setup-Issues.md) | Prometheus configuration |
| 2 | [Jenkins Docker nft-compat Warnings](application/2-Jenkins-Docker-nft-compat-Warnings-Rocky-Linux.md) | Rocky Linux firewall |
| 3 | [Git Remove Sensitive Files](application/3-Git-Remove-Sensitive-Files-From-Repository.md) | Git history cleanup |

---

## Most Critical Lessons

1. **Nested virtualization is fragile** - Sleep/wake, snapshots, and networking all affected
2. **DNS is critical for vCenter** - Many issues traced to name resolution
3. **Snapshots need careful management** - Chain corruption is real and painful
4. **Document as you go** - These cases saved hours during rebuild
