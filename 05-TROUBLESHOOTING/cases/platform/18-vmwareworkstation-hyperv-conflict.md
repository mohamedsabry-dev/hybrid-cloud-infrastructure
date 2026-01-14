VMware Workstation - ESXi VM Fails to Power On After Windows Update

Case Summary
Issue: ESXi virtual machine fails to start in VMware Workstation 25.0.0 after Windows 11 update
Error: "Failed to start the virtual machine" - Module 'ULM' power on failed
Root Cause: Windows Update automatically enabled Hyper-V hypervisor and container features, creating a conflict with VMware Workstation's virtualization layer
Resolution: Disable Windows Hypervisor and conflicting features

Environment Details

Host System
OS: Windows 11 Pro Build 26200.7462 (64-bit)
CPU: AMD Ryzen 7 7435HS (Zen3 architecture)
Hostname: Sabry-PC
VMware Product: VMware Workstation 25.0.0 build 24995812

Virtual Machine Configuration
VM Name: ESXI_Master
Guest OS: vmkernel8 (ESXi 8.x)
vCPUs: 16 cores
Memory: 54272 MB (53 GB)
Virtual Hardware: Version 22
Firmware: EFI
Nested Virtualization: Enabled (vhv.enable = TRUE)

Storage Configuration
SCSI Controller: PVSCSI (scsi0:0) - 150 GB
NVMe Controller: nvme0:0 (2 TB), nvme0:4 (2 TB)
Network: 6 VMXnet3 adapters

Problem Description

Timeline of Events
1. System was running normally with ESXi VM operational
2. Windows 11 update installed (automatic update)
3. System restarted post-update
4. ESXi VM fails to power on with error message
5. Issue timestamp: 2026-01-11 18:03:46 (UTC-02:00)

Error Message
"Failed to start the virtual machine."

Evidence Collection

1. VMware Workstation Log Analysis
Log Location: F:\ESXI_Master\vmware.log
Key Timestamp: 2026-01-11T18:03:46.922Z

Critical Error Entries:
2026-01-11T18:03:46.922Z WARNING ULM: Failed to set up partition, res 0xc0350005.
2026-01-11T18:03:46.922Z INFO Module 'ULM' power on failed.

Error Code Analysis:
0xc0350005: Windows Hypervisor Platform error - "The hypervisor could not perform the operation because the object or value already exists"
Context: VMware's ULM (User-Level Monitor) cannot initialize because another hypervisor is active

Hyper-V Detection:
2026-01-11T18:03:44.597Z INFO IOPL_Init: Hyper-V detected by CPUID

CPUID Analysis:
EBX: 0x7263694d = "Micr" (ASCII)
ECX: 0x666f736f = "osof" (ASCII)
EDX: 0x76482074 = "t Hv" (ASCII)
Result: "Microsoft Hv" - Microsoft Hyper-V hypervisor signature detected

2. Windows System State Analysis

Hypervisor Launch Type Status:
PS> bcdedit /enum | findstr hypervisorlaunchtype
hypervisorlaunchtype    Auto

Expected Value: Off (for VMware compatibility)
Actual Value: Auto (Hyper-V enabled)
Impact: Windows Hypervisor Platform is active, preventing VMware from accessing hardware virtualization

Hyper-V Services Status:
Name       Status StartType
----       ------ ---------
hvhost    Running    Manual
vmcompute Running    Manual

Analysis: These services maintain exclusive control of hardware virtualization features

Windows Optional Features Assessment:
FeatureName                                State
-----------                                -----
VirtualMachinePlatform                  Disabled
HypervisorPlatform                      Disabled
Microsoft-Hyper-V-All                   Disabled
Containers-DisposableClientVM            Enabled  ⚠️
Containers-Server-For-Application-Guard  Enabled  ⚠️
Containers                               Enabled  ⚠️
Containers-HNS                           Enabled  ⚠️
Containers-SDN                           Enabled  ⚠️

Key Findings: Container features enabled by Windows Update require and automatically enable the Windows Hypervisor Platform, even when Hyper-V GUI features are disabled.

Virtualization Based Security Status:
VirtualizationBasedSecurityStatus: 2 (Enabled and running)

VMware Services Status:
Name                    Status StartType
----                    ------ ---------
VMware NAT Service     Running Automatic
VmwareAutostartService Stopped    Manual

Analysis: VMware infrastructure services are healthy and properly configured.

Root Cause Analysis

Primary Cause
Windows Update automatically enabled container-related features that depend on the Windows Hypervisor Platform:
1. Windows Sandbox (Containers-DisposableClientVM)
2. Application Guard containers (Containers-Server-For-Application-Guard)
3. Base container infrastructure (Containers, Containers-HNS, Containers-SDN)

Technical Explanation

Hypervisor Conflict: Only one hypervisor can control hardware virtualization extensions at the operating system level.

When hypervisorlaunchtype is set to Auto:
1. Windows loads hvloader.dll during boot
2. Hypervisor starts in ring -1 (below kernel)
3. Windows kernel runs as a root partition
4. VMware Workstation cannot access VT-x/AMD-V directly
5. ULM initialization fails with error 0xc0350005

ULM Failure Sequence:
1. VMware vmx.exe starts
2. ULM attempts to create VM partition
3. Windows Hypervisor Platform denies access
4. CreatePartition() API returns 0xc0350005
5. ULM initialization fails
6. Power-on operation aborts

Resolution Procedure

Step 1: Disable Windows Hypervisor
bcdedit /set hypervisorlaunchtype off

Expected Output: "The operation completed successfully."

Verification:
bcdedit /enum | findstr hypervisorlaunchtype
Expected Result: hypervisorlaunchtype    Off

Step 2: Disable Container Features
Disable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -NoRestart
Disable-WindowsOptionalFeature -Online -FeatureName Containers-Server-For-Application-Guard -NoRestart

Expected Output:
Path          :
Online        : True
RestartNeeded : True

Step 3: Stop Hyper-V Services
Stop-Service hvhost -Force -ErrorAction SilentlyContinue
Stop-Service vmcompute -Force -ErrorAction SilentlyContinue
Set-Service hvhost -StartupType Disabled -ErrorAction SilentlyContinue
Set-Service vmcompute -StartupType Disabled -ErrorAction SilentlyContinue

Step 4: Restart System
Restart-Computer

Critical: System restart is mandatory for BCD changes to take effect.

Step 5: Post-Restart Verification
bcdedit /enum | findstr hypervisorlaunchtype
Get-Service hvhost, vmcompute | Select-Object Name, Status, StartType
Get-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM | Select-Object State

Expected Results:
- hypervisorlaunchtype Off
- Services: Status = Stopped, StartType = Disabled
- Container feature: State = Disabled

Step 6: Test ESXi VM Power-On
1. Open VMware Workstation
2. Select ESXI_Master VM
3. Click Power On
4. Monitor vmware.log for successful initialization

Success Indicators:
VMX_PowerOn: VMX build 24995812
Module 'ULM' power on succeeded
Transitioned vmx/execState/val to poweredOn

Prevention and Best Practices

1. Windows Update Management
Configure Windows Update to "Notify for download and notify for install"
Review updates before installation to prevent automatic feature enablement

2. Monitor BCD Changes
Create CheckHypervisor.ps1 script:
$hypervisorStatus = bcdedit /enum | Select-String "hypervisorlaunchtype"
if ($hypervisorStatus -match "Auto") {
    Write-Warning "ALERT: Hypervisor has been re-enabled!"
    Write-Host "Run: bcdedit /set hypervisorlaunchtype off"
}

3. Document Known Incompatibilities
Windows Features Incompatible with VMware Workstation:
✗ Hyper-V (all components)
✗ Windows Sandbox
✗ Windows Subsystem for Android (WSA)
✗ Virtual Machine Platform (for WSL2)
✗ Windows Hypervisor Platform
✗ Credential Guard (when using VBS)
✗ Application Guard
✓ WSL1 (compatible - does not use hypervisor)

Knowledge Base References

Microsoft Documentation
- KB4072698: Windows guidance to protect against speculative execution side-channel vulnerabilities
- Windows Hypervisor Platform API: https://docs.microsoft.com/en-us/virtualization/api/

VMware Documentation
- KB2146361: Hyper-V is incompatible with VMware Workstation/Player
- KB1003944: Understanding VMware Workstation and Device Guard/Credential Guard

Related Error Codes
- 0xc0350005: HV_STATUS_OBJECT_IN_USE
- ULM Error: User Level Monitor partition creation failure

Summary

Issue: Windows Update automatically enabled container-based features (Windows Sandbox and Application Guard) which require the Windows Hypervisor Platform, creating an exclusive lock on hardware virtualization (AMD-V) and preventing VMware Workstation's ULM from initializing.

Resolution: Disable Windows Hypervisor Platform by setting hypervisorlaunchtype to off in BCD, disabling Windows Sandbox and container features, stopping Hyper-V services, and restarting the system.

Post-Resolution Verification:
✓ Hypervisor launch type: Off
✓ Hyper-V services: Stopped/Disabled
✓ Container features: Disabled
✓ VMware Workstation: ESXi VM successfully powers on

Case Closed: Resolution successful after disabling conflicting Windows features.
