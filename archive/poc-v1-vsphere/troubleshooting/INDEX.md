# Troubleshooting Index

34 real incident cases documented during POC v1 development.

## Platform (16 cases)

| ID | Issue | Key Learning |
|----|-------|--------------|
| 01 | [vCenter Installation Stage2 Hang](platform/01-vCenter-Installation-Stage2-Hang.md) | DNS resolution required for FQDN |
| 02 | [vCenter Authentication Error SSO](platform/02-vCenter-Authentication-Error-SSO.md) | SSO configuration issues |
| 03 | [vCenter Lifecycle Manager Depot Error](platform/03-vCenter-Lifecycle-Manager-Depot-Error.md) | Depot connectivity |
| 04 | [vCenter Certificate Browser Error](platform/04-vCenter-Certificate-Browser-Error.md) | Browser trust issues |
| 05 | [vCenter Certificate Manager Replace Failed](platform/05-vCenter-Certificate-Manager-Replace-Failed.md) | Certificate replacement process |
| 06 | [vCenter API SSL Error After Root CA](platform/06-vCenter-API-SSL-Error-After-Root-CA.md) | SSL chain validation |
| 08 | [Windows Host Sleep Network Break](platform/08-Windows-Host-Sleep-Network-Break.md) | Sleep mode breaks nested VMs |
| 09 | [Windows Host NAT vs Bridge](platform/09-Windows-Host-NAT-vs-Bridge.md) | Network mode decision |
| 10 | [vCenter8 vApp Config Not Persisting](platform/10-vCenter8-vApp-Config-Not-Persisting.md) | vApp configuration gotchas |
| 11 | [FreeIPA Time Sync Clock Skew](platform/11-FreeIPA-Time-Sync-Clock-Skew.md) | Kerberos time requirements |
| 12 | [FreeIPA SSSD Cache Not Updating](platform/12-FreeIPA-SSSD-Cache-Not-Updating.md) | SSSD cache invalidation |
| 13 | [vCenter Backup Failure After IP Change](platform/13-vCenter-Backup-Failure-After-IP-Change.md) | IP change impacts |
| 14 | [vSphere Lifecycle Manager Plugin Download Error](platform/14-vSphere-Lifecycle-Manager-Plugin-Download-Error.md) | Plugin download issues |
| 15 | [vCenter Firewall Invalid Interface Error](platform/15-vCenter-Firewall-Invalid-Interface-Error.md) | Firewall configuration |
| 16 | [ESXi Master AutoProtect Snapshot Performance](platform/16-ESXi-Master-AutoProtect-Snapshot-Performance-Degradation.md) | Snapshot performance impact |
| 18 | [VMware Workstation Hyper-V Conflict](platform/18-vmwareworkstation-hyperv-conflict.md) | Hypervisor conflicts |

## Storage (10 cases)

| ID | Issue | Key Learning |
|----|-------|--------------|
| 01 | [VMDK Snapshot Corruption](storage/01-vmdk-snapshot-corruption.md) | Snapshot chain integrity |
| 02 | [NAS Snapshot Sizing Failure](storage/02-nas-snapshot-sizing-failure.md) | Snapshot space planning |
| 03 | [Disk Race Condition Disaster](storage/03-disk-race-condition-disaster.md) | Concurrent disk access |
| 06 | [Thick to Thin Conversion](storage/06-thick-to-thin-conversion.md) | Disk format conversion |
| 07 | [NAS Memory Starvation](storage/07-nas-memory-starvation.md) | NAS resource limits |
| 08a | [NAS Backup Strategy Optimization](storage/08-NAS-Backup-Strategy-Optimization.md) | Backup optimization |
| 08b | [VMware Snapshot Chain Corruption](storage/08-VMware-Snapshot-Chain-Corruption.md) | Chain repair |
| 09 | [Thick Provisioned Snapshot Size](storage/09-Thick-Provisioned-Snapshot-Size.md) | Thick disk snapshot behavior |
| 10 | [Application Aware Backup Loop Device Errors](storage/10-Application-Aware-Backup-Loop-Device-Errors.md) | App-aware backup issues |
| 11 | [Snapshot Chain Corruption Sleep Mode](storage/11-Snapshot-Chain-Corruption-Sleep-Mode.md) | Sleep mode corruption |

## Network (5 cases)

| ID | Issue | Key Learning |
|----|-------|--------------|
| 04 | [Promiscuous Mode Nested](network/04-promiscuous-mode-nested.md) | Nested VM networking |
| 05 | [Duplicate Packets Loop](network/05-duplicate-packets-loop.md) | Network loop detection |
| 06 | [pfSense Poweroff](network/06-pfsense-poweroff.md) | pfSense shutdown handling |
| 07 | [Windows Host Network Loops](network/07-Windows-Host-Network-Loops.md) | Host network configuration |
| 08 | [Static Route Loop SSH Disconnect](network/08-Static-Route-Loop-SSH-Disconnect.md) | Routing table issues |

## Application (3 cases)

| ID | Issue | Key Learning |
|----|-------|--------------|
| 01 | [Prometheus Setup Issues](application/01-Prometheus-Setup-Issues.md) | Prometheus configuration |
| 02 | [Jenkins Docker nft-compat Warnings](application/02-Jenkins-Docker-nft-compat-Warnings-Rocky-Linux.md) | Rocky Linux firewall |
| 17 | [Git Remove Sensitive Files](application/17-Git-Remove-Sensitive-Files-From-Repository.md) | Git history cleanup |

## Statistics

- **Total cases:** 34
- **Platform issues:** 16 (47%)
- **Storage issues:** 10 (29%)
- **Network issues:** 5 (15%)
- **Application issues:** 3 (9%)

## Most Critical Lessons

1. **Nested virtualization is fragile** - Sleep/wake, snapshots, and networking all affected
2. **DNS is critical for vCenter** - Many issues traced to name resolution
3. **Snapshots need careful management** - Chain corruption is real and painful
4. **Document as you go** - These cases saved hours during rebuild
