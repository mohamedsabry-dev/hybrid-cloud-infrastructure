================================================================================
CONFIGURATION REFERENCE
Disaster Recovery Guide - Part 7
================================================================================
Last Updated: 2026-01-03
Back to: [README.md](README.md)

Quick reference for IP addresses, file paths, ports, and configuration settings.

================================================================================
TABLE OF CONTENTS
================================================================================
1. IP Address Summary
2. File Paths & Scripts
3. User Accounts Summary
4. PowerShell Requirements
5. VMware Auto-Startup Settings
6. Veeam Configuration
7. Network Port Requirements

================================================================================
1. IP ADDRESS SUMMARY
================================================================================

## Network Segments

**Home Network (External):**
- Network: 192.x.x..##
- Router: 192.x.x..##
- Windows Host: 192.x.x.## && 10.0.20.1

**Internal Network (Isolated):**
- Network: 10.0.20.x
- Gateway: 10.0.20.170 (pfSense LAN)

## Infrastructure Components

| Component              | IP Address    | Network Segment | Purpose                |
|------------------------|---------------|-----------------|------------------------|
| Windows Host           | 192.x.x.##/10.0.20.1    | Home Network    | Physical laptop        |
| ESXi Master            | 10.0.20.100   | Internal        | Main hypervisor        |
| Production ESXi        | 10.0.20.101   | Internal        | Nested hypervisor      |
| DR ESXi                | 10.0.20.102   | Internal        | Disaster recovery      |
| vCenter                | 10.0.20.89    | Internal        | Management             |
| IPA (FreeIPA)          | 10.0.20.89    | Internal        | DNS/Auth               |
| pfSense WAN            | 192.x.x.## | Home Network    | External gateway       |
| pfSense LAN            | 10.0.20.170   | Internal        | Internal gateway       |
| NAS Storage            | 10.0.20.x     | Internal        | Shared storage         |
| Veeam (Inner)          | 10.0.20.195   | Internal        | Backup server (Win)    |

## Application VMs (Inner Layer)

| VM Name       | IP Address | ESXi Host           | Purpose              |
|---------------|------------|---------------------|----------------------|
| K8s Master    | 10.0.20.x  | Production ESXi     | K8s control plane    |
| K8s Worker-1  | 10.0.20.x  | Production ESXi     | K8s worker node      |
| K8s Worker-2  | 10.0.20.x  | Production ESXi     | K8s worker node      |
| K8s Worker-3  | 10.0.20.x  | Production ESXi     | K8s worker node      |
| Vault-01      | 10.0.20.x  | Production ESXi     | Vault cluster node   |
| Vault-02      | 10.0.20.x  | Production ESXi     | Vault cluster node   |
| Vault-03      | 10.0.20.x  | Production ESXi     | Vault cluster node   |
| Ansible       | 10.0.20.x  | Production ESXi     | Automation           |
| Jenkins       | 10.0.20.x  | Production ESXi     | CI/CD                |
| Monitor       | 10.0.20.x  | Production ESXi     | Monitoring           |

================================================================================
2. FILE PATHS & SCRIPTS
================================================================================

## PowerShell Scripts (Windows Host)

**Runtime Location (Production):**
- Installed Path: `C:\Scripts\`

**Source Location (Documentation):**
- Reference Copies: `DR/Scripts/` (in this documentation folder)

**Main Scripts:**
- Battery Monitor: `C:\Scripts\BatteryMonitor.ps1`
- Emergency Shutdown: `C:\Scripts\EmergencyLabShutdown.ps1`

**Credential Files:**
- Inner Veeam: `C:\Scripts\InnerWindowsCreds.xml`
- vCenter: `C:\Scripts\vCenterCreds.xml`

**Logs:**
- Shutdown Log: `C:\Scripts\ShutdownLog.txt`

**Dry Run Tests:**
- Credential Test: `C:\Scripts\Dry Run\Test-LabCreds.ps1`
- Veeam Visibility: `C:\Scripts\Dry Run\Test-VeeamVisibility.ps1`
- Graceful Stop: `C:\Scripts\Dry Run\Test-VeeamStop.ps1`
- Hard Kill Test: `C:\Scripts\Dry Run\Test-VeeamStop_HardKill.ps1`
- Remote Kill Test: `C:\Scripts\Dry Run\Test-VeeamStop_RemoteKill.ps1`

**Note:** Script source files are maintained in `Scripts/` folder alongside this documentation for version control and reference.

## VMware Workstation

**ESXi Master VM:**
- VMX File: `F:\ESXI_Master\ESXi_Master.vmx`
- vmrun Utility: `C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe`

## Ansible Playbooks

**Emergency User Deployment:**
- Playbook: `/03-AUTOMATION/ansible-playbooks/os-services/01-emergency-user.yml`
- Script: `/03-AUTOMATION/scripts/create-emergency-user.sh`

## Backup Repositories

**Outer Veeam (Windows Host):**
- Repository: Default Backup Repository
- Path: `D:\Veeam_Backups\`

**Inner Veeam (NAS Storage):**
- Primary Repository: Backup Repository Host
- Path: `/mnt/backups/veeam/`

**Inner Veeam (Secondary - Optional):**
- Secondary Repository: Backup Repository - Host (SMB)
- Path: `\\10.0.20.1\Backup`
- Status: Configured but not used

**vCenter Built-in Backup:**
- Target: NAS Storage
- Path: `/mnt/datastor2`

================================================================================
3. USER ACCOUNTS SUMMARY
================================================================================

## Backup Access Accounts

| Account           | Type   | Systems                    | Auth Method         | Purpose            |
|-------------------|--------|----------------------------|---------------------|--------------------|
| veeam@home.lab    | Domain | 10 VMs (internal)          | Passwordless sudo   | Automated backups  |
| veeam_emergency   | Local  | 10 VMs (internal)          | SSH key             | Backup fallback    |
| veeam_emergency   | Local  | Infra (outer layer)        | Password            | Manual backups     |
| administrator@vsphere.local | Domain | vCenter          | Password            | Management         |

## Credential Storage

**Vault (Inner Layer SSH Keys):**
- Path: `secret/data/infra/veeam_emergency`
- Fields: private_key, public_key

**Windows DPAPI (PowerShell Scripts):**
- Inner Veeam: `C:\Scripts\InnerWindowsCreds.xml`
- vCenter: `C:\Scripts\vCenterCreds.xml`

**Password Storage (Outer Layer):**
- Location: Windows Host secure storage
- Protection: Encrypted using Windows mechanisms

================================================================================
4. POWERSHELL REQUIREMENTS
================================================================================

## Version Requirements

**Required:** PowerShell 7+ (pwsh)
**Installation:** https://aka.ms/powershell
**Verification:** `$PSVersionTable.PSVersion.Major`

**Why PowerShell 7?**
- Veeam v13 modules incompatible with PowerShell 5
- Script auto-detects and relaunches in pwsh if needed

## Required Modules

**Veeam.Backup.PowerShell:**
- Version: v13
- Path: `C:\Program Files\Veeam\Backup and Replication\Console`
- Import: `Import-Module Veeam.Backup.PowerShell`

**VMware.PowerCLI:**
- Installation: `Install-Module VMware.PowerCLI -Scope CurrentUser`
- Usage: Connect-VIServer, Stop-VMHost cmdlets

## Script Configuration Variables

**BatteryMonitor.ps1:**
```powershell
$TriggerPercent  = 75    # Battery threshold
$ShutdownScript  = "C:\Scripts\EmergencyLabShutdown.ps1"
$CheckInterval   = 30    # Check every 30 seconds
```

**EmergencyLabShutdown.ps1:**
```powershell
$LogPath         = "C:\Scripts\ShutdownLog.txt"
$InnerCredPath   = "C:\Scripts\InnerWindowsCreds.xml"
$vCenterCredPath = "C:\Scripts\vCenterCreds.xml"
$InnerVeeamIP    = "10.0.20.195"
$vCenterIP       = "10.0.20.89"
$NestedWorkers   = @("10.0.20.101", "10.0.20.102")
$MasterESXi      = "10.0.20.100"
$MasterVMX       = "F:\ESXI_Master\ESXi_Master.vmx"
```

================================================================================
5. VMWARE AUTO-STARTUP SETTINGS
================================================================================

## ESXi Master (10.0.20.100)

**Configuration Path:** Host > Configure > Virtual Machine Startup/Shutdown

| Order | VM Name               | Startup Delay | Shutdown Delay |
|-------|-----------------------|---------------|----------------|
| 1     | IPA                   | 60s           | 60s            |
| 2     | pfSense FW            | 60s           | 60s            |
| 3     | NAS Storage           | 60s           | 60s            |
| 4     | Production Server     | 60s           | 60s            |
| 5     | VMware vCenter Server | 100s          | 60s            |
| 6     | Veeam                 | 200s          | 20s            |

**Settings:**
- Mode: Automatic Ordered
- Shutdown Action: Guest shutdown (via VMware Tools)

## Production ESXi (10.0.20.101)

**Configuration Path:** Host > Configure > Virtual Machine Startup/Shutdown

| Order | VM Name       | Startup Delay | Shutdown Delay |
|-------|---------------|---------------|----------------|
| 1     | Ansible       | 60s           | 60s            |
| 2     | Vault-01      | 60s           | 60s            |
| 3     | Vault-02      | 0s            | 0s             |
| 4     | Vault-03      | 0s            | 0s             |
| 5     | Monitor       | 60s           | 60s            |
| 6     | Jenkins       | 60s           | 60s            |
| 7     | K8s-Master    | 60s           | 60s            |
| 8     | K8s-Worker-1  | 60s           | 60s            |
| 9     | K8s-Worker-2  | 0s            | 0s             |
| 10    | K8s-Worker-3  | 0s            | 0s             |

**Critical Requirement:** VMware Tools must be installed on ALL VMs

================================================================================
6. VEEAM CONFIGURATION
================================================================================

## Outer Veeam (Windows Host)

**Location:** Windows Host (10.0.20.1)
**Repository:** Default Backup Repository (Host storage)
**Connection:** vCenter (10.0.20.89)

**Backup Jobs:**
- Vault Cluster (3 VMs) - 8:20 PM daily
- K8s Workers (3 VMs) - 8:45 PM daily
- Automation VMs (2 VMs) - 9:10 PM daily
- K8s Master (1 VM) - 9:35 PM daily
- Monitor (1 VM) - 9:50 PM daily

**Total:** 10 VMs (at Community Edition limit)

## Inner Veeam (10.0.20.195)

**Location:** Windows Server 2022 VM on ESXi Master
**Repository:** NAS Storage (NFS mount)
**Connection:** Standalone ESXi Master (10.0.20.100)

**Backup Jobs:**
- pfSense (1 VM) - 7:50 PM daily
- IPA (1 VM) - 10:30 PM daily
- Veeam Inner (1 VM) - 11:15 PM daily
- NAS Server (1 VM) - Manual
- Production ESXi (1 VM) - Manual
- DR ESXi (1 VM) - Manual
- vCenter (1 VM) - Manual

**Total:** 7 VMs (3 automated, 4 manual)

## Veeam Performance Settings

**Storage Access Method:** Direct Storage Access (via VMware APIs)
**Network Mode:** DISABLED as fallback
**Concurrency:** 1 concurrent task maximum
**Network Throttle:** 200 MB/s (if network mode enabled)

**Job Timing:**
- Each job has 10-minute buffer before next job starts
- Based on real-world performance testing
- Prevents job queue collisions during emergency shutdown

================================================================================
7. NETWORK PORT REQUIREMENTS
================================================================================

## Veeam Access

**SSH (Guest Processing):**
- Port: 22
- Protocol: SSH
- Purpose: Guest processing, application-aware backups

**VMware SOAP:**
- Port: 902
- Protocol: VMware SOAP
- Purpose: ESXi management and backup operations

**HTTPS (vCenter API):**
- Port: 443
- Protocol: HTTPS
- Purpose: vCenter API access for backup orchestration

**WinRM (Remote Veeam):**
- Port: 5985
- Protocol: WinRM
- Purpose: Remote Veeam control (Inner Veeam from Windows Host)

## vCenter Access

**HTTPS (Management API):**
- Port: 443
- Protocol: HTTPS
- Purpose: Web UI and management API

**VMware SOAP:**
- Port: 902
- Protocol: VMware SOAP
- Purpose: ESXi communication and orchestration

## ESXi Access

**SSH (Host Management):**
- Port: 22
- Protocol: SSH
- Purpose: Direct host management

**HTTPS (Host API):**
- Port: 443
- Protocol: HTTPS
- Purpose: Host API access

**VMware SOAP:**
- Port: 902
- Protocol: VMware SOAP
- Purpose: VM operations and management

================================================================================
QUICK REFERENCE COMMANDS
================================================================================

## Battery Monitoring

**Start Monitoring:**
```powershell
C:\Scripts\BatteryMonitor.ps1
```

**Check Battery Status:**
```powershell
Get-CimInstance -ClassName Win32_Battery
```

## Veeam Operations

**Import Module (PowerShell 7):**
```powershell
Import-Module Veeam.Backup.PowerShell
```

**List Running Jobs:**
```powershell
Get-VBRBackupSession | Where-Object {$_.State -eq 'Working'}
```

**Stop Job (Hard Kill):**
```powershell
$Job = Get-VBRJob -Name "JobName"
Stop-VBRJob -Job $Job
```

## VMware Operations

**Connect to vCenter:**
```powershell
Connect-VIServer -Server 10.0.20.89
```

**Shutdown ESXi Host:**
```powershell
Stop-VMHost -VMHost 10.0.20.100 -Force -Confirm:$false
```

**Check VM Status:**
```powershell
Get-VM | Select Name, PowerState
```

## Emergency Procedures

**Abort Windows Shutdown:**
```powershell
shutdown /a
```

**Check Shutdown Log:**
```powershell
Get-Content "C:\Scripts\ShutdownLog.txt" -Tail 100
```

**Test Credentials:**
```powershell
.\Dry Run\Test-LabCreds.ps1
```

================================================================================
MAINTENANCE SCHEDULES
================================================================================

## Daily Tasks (Automated)

**7:50 PM - 11:15 PM:** Automated backup window
- pfSense (7:50 PM)
- Vault Cluster (8:20 PM)
- K8s Workers (8:45 PM)
- Automation VMs (9:10 PM)
- K8s Master (9:35 PM)
- Monitor (9:50 PM)
- IPA (10:30 PM)
- Veeam Inner (11:15 PM)

## Weekly Tasks (Manual)

- Review backup job completion emails
- Check Veeam repository space
- Verify battery monitoring script running

## Monthly Tasks (Manual)

- Test emergency shutdown (simulated trigger)
- Review shutdown logs
- Verify credential files valid
- Update documentation if changes made

## Quarterly Tasks (Manual)

- Full DR drill (actual battery disconnect)
- Review and update this documentation
- Test all dry-run scripts
- Verify VMware Tools on all VMs

================================================================================
TROUBLESHOOTING QUICK REFERENCE
================================================================================

## Common Issues

**Battery Monitor Not Running:**
```powershell
# Check Task Scheduler
Get-ScheduledTask | Where-Object {$_.TaskName -like "*Battery*"}

# Manually start
C:\Scripts\BatteryMonitor.ps1
```

**Veeam Module Not Loading:**
```powershell
# Check PowerShell version
$PSVersionTable.PSVersion.Major  # Must be 7+

# Launch PowerShell 7
pwsh
```

**vCenter Connection Failed:**
```powershell
# Check vCenter reachable
Test-Connection -ComputerName 10.0.20.89

# Verify credentials
Import-Clixml -Path "C:\Scripts\vCenterCreds.xml"
```

**Domain User Not Working:**
```bash
# On VM, check IPA connectivity
ping 10.0.20.89
getent passwd veeam@home.lab

# Use emergency user instead
ssh -i /path/to/key veeam_emergency@<vm-ip>
```

================================================================================
RELATED DOCUMENTATION
================================================================================

- [README.md](README.md) - Main overview and navigation
- [01-Backup-Strategy.md](01-Backup-Strategy.md) - Backup configuration details
- [02-User-Accounts.md](02-User-Accounts.md) - User account setup and management
- [03-Emergency-Shutdown.md](03-Emergency-Shutdown.md) - Script implementation
- [06-Design-Decisions.md](06-Design-Decisions.md) - Why these settings?

Back to: [README.md](README.md)

================================================================================
END OF CONFIGURATION REFERENCE
================================================================================
