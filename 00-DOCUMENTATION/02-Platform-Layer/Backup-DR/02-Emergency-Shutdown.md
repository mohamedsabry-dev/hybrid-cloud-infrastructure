================================================================================
EMERGENCY SHUTDOWN SYSTEM
Disaster Recovery Guide - Part 3
================================================================================
Last Updated: 2026-01-03
Back to: [README.md](README.md)

================================================================================
TABLE OF CONTENTS
================================================================================
1. System Overview
2. Battery Monitoring (Phase 1)
3. Shutdown Phases (2-6)
4. Script Components & File Structure
5. Testing & Validation Procedures

================================================================================
1. SYSTEM OVERVIEW
================================================================================

The DR system protects against unexpected power outages by monitoring laptop
battery and triggering graceful shutdown when power is lost.

## Two PowerShell Scripts Working in Tandem

1. **BatteryMonitor.ps1** - Continuous monitoring daemon
2. **EmergencyLabShutdown.ps1** - Shutdown orchestration

## Architecture Diagram

```
┌──────────────────────────────────────────────────┐
│ Windows Host (Laptop)                            │
│                                                   │
│  [AC Power Loss Detected]                        │
│           ↓                                       │
│  ┌─────────────────────┐                         │
│  │ BatteryMonitor.ps1  │ ← Auto-starts at login  │
│  │ - Poll every 30s    │   (Task Scheduler)      │
│  │ - Trigger: 75%      │                         │
│  └──────────┬──────────┘                         │
│             │ Battery ≤ 75% & Discharging         │
│             ↓                                     │
│  ┌─────────────────────────────────┐             │
│  │ EmergencyLabShutdown.ps1        │             │
│  │ ┌─────────────────────────────┐ │             │
│  │ │ Phase 0: Check PowerShell 7 │ │             │
│  │ │ Phase 2: Kill Veeam Jobs    │ │             │
│  │ │ Phase 3: Shutdown Nested    │ │             │
│  │ │ Phase 4: Shutdown Master    │ │             │
│  │ │ Phase 5: VMware Workstation │ │             │
│  │ │ Phase 6: Shutdown Laptop    │ │             │
│  │ └─────────────────────────────┘ │             │
│  └─────────────────────────────────┘             │
└──────────────────────────────────────────────────┘
```

## Timeline Breakdown

**Total Shutdown Time:** 10-13 minutes
- Phase 2: < 1 minute (Veeam kills)
- Phase 3: 3 minutes (nested ESXi)
- Phase 4: 3 minutes (master ESXi)
- Phase 5: 3 minutes (fallback if needed)
- Phase 6: Instant
- **Buffer:** 2 minutes for Workstation auto-snapshot

**Battery Runtime at 75%:** ~15-20 minutes remaining
**Safety Margin:** 5-7 minutes

See [06-Design-Decisions.md](06-Design-Decisions.md#why-75-battery-threshold) for threshold rationale.

================================================================================
2. BATTERY MONITORING (PHASE 1)
================================================================================

## BatteryMonitor.ps1

**Script Location:** `C:\Scripts\BatteryMonitor.ps1`
**Startup Method:** Auto-starts via Task Scheduler on user login

### Configuration Variables

```powershell
$TriggerPercent  = 75    # Trigger threshold
$ShutdownScript  = "C:\Scripts\EmergencyLabShutdown.ps1"
$CheckInterval   = 30    # Check every 30 seconds
```

### Monitoring Logic

```powershell
$Battery = Get-CimInstance -ClassName Win32_Battery
$Percent = $Battery.EstimatedChargeRemaining
$Status  = $Battery.BatteryStatus  # 1=Discharging, 2=AC

# Trigger Condition: Discharging AND below threshold
if ($Status -ne 2 -and $Percent -le $TriggerPercent) {
    & $ShutdownScript  # Execute emergency shutdown
    break
}
```

### Trigger Conditions (AND Logic)

1. Battery status ≠ 2 (not on AC power)
2. Battery level ≤ 75%

### Visual Console Output

```
==========================================
   LIVE BATTERY MONITORING STATION
   Target Trigger: 75%
   Action: EXECUTE KILL SWITCH
==========================================

[14:23:15] Battery: 87% | Mode: AC POWER (Safe)
[14:23:45] Battery: 86% | Mode: AC POWER (Safe)
[14:24:15] Battery: 76% | Mode: DISCHARGING (Danger)
[14:24:45] Battery: 75% | Mode: DISCHARGING (Danger)

----------------------------------------
[CRITICAL] THRESHOLD REACHED (75%)
[CRITICAL] INITIATING EMERGENCY SHUTDOWN...
----------------------------------------
```

## Task Scheduler Configuration

**Task Name:** Battery Monitor - Emergency Shutdown
**Trigger:** At user logon
**Action:** Run PowerShell script
**Program:** `C:\Windows\System32\cmd.exe`
**Arguments:** `/k "powershell.exe -ExecutionPolicy Bypass -NoExit -File C:\Scripts\BatteryMonitor.ps1"`

**Settings:**
- Run with highest privileges: No (runs as user)
- Run whether user logged on or not: No (requires active session)
- Wake computer to run: No
- Stop if computer switches to battery: No (opposite - must run on battery!)

**Desktop Shortcut (Optional):**
```
Target: C:\Windows\System32\cmd.exe /k "powershell.exe -ExecutionPolicy Bypass -NoExit -File C:\Scripts\BatteryMonitor.ps1"
Purpose: Keep console window visible during monitoring
```

================================================================================
3. SHUTDOWN PHASES (2-6)
================================================================================

## Phase 0: PowerShell Version Check (Self-Correction)

**Purpose:** Ensure PowerShell 7 is being used (Veeam v13 requirement)

```powershell
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "Detected old PowerShell 5. Restarting in PowerShell 7..."
    Start-Process pwsh -ArgumentList "-File `"$ScriptPath`"" -Wait
    exit
}
```

**Why PowerShell 7?**
- Veeam v13 modules incompatible with PowerShell 5
- Script auto-detects and relaunches in pwsh if needed
- Prevents silent failures due to module import errors

**Credential Loading:**
```powershell
$InnerCreds   = Import-Clixml -Path "C:\Scripts\InnerWindowsCreds.xml"
$vCenterCreds = Import-Clixml -Path "C:\Scripts\vCenterCreds.xml"
```

**Fallback:** If credentials missing, immediate laptop shutdown

---

## Phase 2: Stop Veeam Backup Jobs (Hard Kill)

**Purpose:** Immediately terminate running backups to free resources

**Function:** `Stop-Veeam-Safe`

**Targets:**
1. Inner Veeam (10.0.20.195) - Remote via WinRM
2. Outer Veeam (Local Host) - Direct module access

**Why Hard Kill?**
From testing: Graceful stop can wait indefinitely during disk block transfers
- Soft stop: Waits for current block to finish (can take hours)
- Hard stop: Immediate termination (backup may need repair)
- Trade-off: Corrupted backup (recoverable) < total data loss (unrecoverable)

See [06-Design-Decisions.md](06-Design-Decisions.md#why-hard-kill-veeam-jobs) for full analysis.

**Implementation (Inner Veeam - Remote):**
```powershell
Invoke-Command -ComputerName 10.0.20.195 -Credential $InnerCreds -ScriptBlock {
    $Inner = pwsh -Command {
        Import-Module Veeam.Backup.PowerShell
        $Sessions = Get-VBRBackupSession | Where-Object {$_.State -eq 'Working'}

        foreach ($s in $Sessions) {
            $Job = Get-VBRJob | Where-Object { $_.Id -eq $s.JobId }
            Stop-VBRJob -Job $Job  # NO -Gracefully flag = hard kill
        }
    }
}
```

**Implementation (Outer Veeam - Local):**
```powershell
pwsh -Command {
    Import-Module Veeam.Backup.PowerShell
    $Sessions = Get-VBRBackupSession | Where-Object {$_.State -eq 'Working'}

    foreach ($s in $Sessions) {
        $Job = Get-VBRJob | Where-Object { $_.Id -eq $s.JobId }
        Stop-VBRJob -Job $Job
    }
}
```

**Error Handling:**
- Remote Veeam unreachable: Skip and continue (logged as warning)
- No active jobs: Continue to next phase
- Module import failure: Caught and logged

---

## Phase 3: Shutdown Nested ESXi Servers

**Targets:**
- Production ESXi: 10.0.20.101
- DR ESXi: 10.0.20.102

**Method:** vCenter API (Stop-VMHost cmdlet)

**Connection:**
```powershell
Connect-VIServer -Server 10.0.20.89 -Credential $vCenterCreds
```

**Shutdown Signal:**
```powershell
foreach ($hostIP in @("10.0.20.101", "10.0.20.102")) {
    # -Force bypasses "Maintenance Mode" check
    # Triggers standard guest shutdown sequence (not power off)
    Stop-VMHost -VMHost $hostIP -Force -Confirm:$false
}
```

**Important: -Force Flag**
- Does NOT mean "hard power off"
- Bypasses maintenance mode requirement
- Triggers standard graceful shutdown
- VMs follow auto-shutdown sequence (see [04-VM-Startup-Shutdown.md](04-VM-Startup-Shutdown.md))

**Wait Period:** 3 minutes (180 seconds)
```powershell
$Timer = 0
$MaxWait = 180
do {
    Start-Sleep -Seconds 10
    $Timer += 10
    $Alive = Test-Connection -ComputerName $NestedWorkers -Count 1 -Quiet
} while ($Alive -and $Timer -lt $MaxWait)
```

**Outcome:**
- Success: Nested ESXi servers shutdown, VMs gracefully stopped
- Timeout: Log warning and proceed (master shutdown will force it)

---

## Phase 4: Shutdown Master ESXi

**Target:** ESXi Master (10.0.20.100)

**Method:** vCenter API (Stop-VMHost cmdlet)

**Shutdown Signal:**
```powershell
Stop-VMHost -VMHost 10.0.20.100 -Force -Confirm:$false
```

**Auto-Shutdown Sequence:**
ESXi Master has configured VM shutdown order (see [04-VM-Startup-Shutdown.md](04-VM-Startup-Shutdown.md)):
1. IPA - 60s delay
2. pfSense - 60s delay
3. NAS - 60s delay
4. Production ESXi (nested) - 60s delay
5. vCenter - 100s delay
6. Veeam (inner) - 200s delay

**Wait Period:** 3 minutes (180 seconds)
```powershell
$Timer = 0
$MaxWait = 180
do {
    Start-Sleep -Seconds 10
    $Timer += 10
    $MasterAlive = Test-Connection -ComputerName 10.0.20.100 -Count 1 -Quiet
} while ($MasterAlive -eq $true -and $Timer -lt $MaxWait)
```

**Fallback:** If still alive after 3 minutes, proceed to Phase 5

---

## Phase 5: VMware Workstation Fallback (Soft Stop)

**Trigger:** Master ESXi still responsive after Phase 4

**Method:** VMware Workstation `vmrun` command-line utility

**Implementation:**
```powershell
$VmrunPath = "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe"
$MasterVMX = "F:\ESXI_Master\ESXi_Master.vmx"

Start-Process -FilePath $VmrunPath `
              -ArgumentList "-T ws stop `"$MasterVMX`" soft" `
              -Wait -NoNewWindow
```

**"soft" Parameter:**
- Equivalent to pressing "Power" button in Workstation GUI
- Sends ACPI shutdown signal to guest OS
- NOT a hard power-off
- Allows ESXi to run shutdown sequence

**Wait Period:** 3 minutes (180 seconds)

**Final Check (Last Resort):**
```powershell
$FinalCheck = Test-Connection -ComputerName 10.0.20.100 -Count 1 -Quiet
if ($FinalCheck) {
    # LAST RESORT: Hard kill VM process
    Stop-Process -Name "vmware-vmx" -Force
    Start-Sleep -Seconds 120  # Wait for clean-up
}
```

**Hard Kill (Absolute Last Resort):**
- Kills `vmware-vmx` process (ESXi Master VM)
- Simulates pulling power cord
- Risk: Potential for data corruption
- Justification: Better than battery death during operation

---

## Phase 6: Shutdown Laptop

**Final Step:**
```powershell
Write-Log "PHASE 6: Goodnight." "Cyan"
Stop-Computer
```

**Timing:**
ESXi Master snapshot by VMware Workstation completes before this (2 minutes)

================================================================================
4. SCRIPT COMPONENTS & FILE STRUCTURE
================================================================================

## File Structure

```
C:\Scripts\
├── BatteryMonitor.ps1           # Main monitoring daemon
├── EmergencyLabShutdown.ps1     # Shutdown orchestration
├── InnerWindowsCreds.xml        # Encrypted creds (Inner Veeam)
├── vCenterCreds.xml             # Encrypted creds (vCenter)
├── ShutdownLog.txt              # Execution log (auto-generated)
└── Dry Run\
    ├── Test-LabCreds.ps1        # Verify credential files
    ├── Test-VeeamVisibility.ps1 # Check Veeam module access
    ├── Test-VeeamStop.ps1       # Test graceful stop
    ├── Test-VeeamStop_HardKill.ps1     # Test hard kill
    └── Test-VeeamStop_RemoteKill.ps1   # Test remote execution
```

## Credential Management

### Creating Encrypted Credential Files

**InnerWindowsCreds.xml:**
```powershell
$InnerCreds = Get-Credential -Message "Enter Inner Veeam (10.0.20.195) credentials"
$InnerCreds | Export-Clixml -Path "C:\Scripts\InnerWindowsCreds.xml"
```

**vCenterCreds.xml:**
```powershell
$vCenterCreds = Get-Credential -Message "Enter vCenter (administrator@vsphere.local)"
$vCenterCreds | Export-Clixml -Path "C:\Scripts\vCenterCreds.xml"
```

**Security:**
- Encrypted using Windows Data Protection API (DPAPI)
- Tied to user account on local machine
- Cannot be decrypted on different machine or by different user
- Safe to store in file system (user-scoped encryption)

### Importing Credentials in Scripts

```powershell
if ((Test-Path $InnerCredPath) -and (Test-Path $vCenterCredPath)) {
    $InnerCreds   = Import-Clixml -Path $InnerCredPath
    $vCenterCreds = Import-Clixml -Path $vCenterCredPath
} else {
    Write-Log "ERROR: Credentials missing! Halting." "Red"
    Stop-Computer
    exit
}
```

**Fallback Behavior:** If credentials unavailable, immediate laptop shutdown

## EmergencyLabShutdown.ps1 Configuration Variables

```powershell
$LogPath         = "C:\Scripts\ShutdownLog.txt"
$InnerCredPath   = "C:\Scripts\InnerWindowsCreds.xml"
$vCenterCredPath = "C:\Scripts\vCenterCreds.xml"
$InnerVeeamIP    = "10.0.20.195"
$vCenterIP       = "10.0.20.89"
$NestedWorkers   = @("10.0.20.101", "10.0.20.102")
$MasterESXi      = "10.0.20.100"
$MasterVMX       = "F:\ESXI_Master\ESXi_Master.vmx"
$VmrunPath       = "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe"
```

================================================================================
5. TESTING & VALIDATION PROCEDURES
================================================================================

## Phase 1: Component Testing (Dry Runs)

**Purpose:** Validate individual functions without full shutdown

**1. Credential Validation**
```powershell
.\Dry Run\Test-LabCreds.ps1
```
- Verifies credential files exist and decrypt
- Confirms paths are correct

**2. Veeam Module Access**
```powershell
.\Dry Run\Test-VeeamVisibility.ps1
```
- Checks PowerShell 7 availability
- Confirms Veeam module loads
- Lists current backup sessions

**3. Veeam Stop Behavior**
```powershell
# Start a test backup job first
.\Dry Run\Test-VeeamStop.ps1          # Test graceful
.\Dry Run\Test-VeeamStop_HardKill.ps1 # Test immediate
```
- Validates job termination works
- Compares graceful vs. hard kill timing
- Confirms no module errors

**4. Remote Execution**
```powershell
.\Dry Run\Test-VeeamStop_RemoteKill.ps1
```
- Tests WinRM to Inner Veeam (10.0.20.195)
- Validates credential-based authentication
- Confirms nested pwsh execution works

---

## Phase 2: Simulated Battery Trigger

**Controlled Test:** Modify `BatteryMonitor.ps1` trigger threshold

**Before:**
```powershell
$TriggerPercent = 75
```

**For Drill:**
```powershell
$TriggerPercent = 90  # Trigger at current battery level - 1%
```

**Procedure:**
1. Set trigger to 1% below current battery level
2. Disconnect AC power
3. Wait 30 seconds for next poll
4. Monitor script execution in console window
5. **CRITICAL:** Manually cancel shutdown before laptop powers off

**Cancellation:**
```powershell
# In another PowerShell window (as admin)
shutdown /a  # Abort shutdown
```

---

## Phase 3: Full DR Drill

**WARNING:** This will shut down entire lab environment

**Preparation:**
1. Schedule maintenance window (no active workloads)
2. Notify users (if applicable)
3. Verify all backups are current
4. Document current state (snapshots, config exports)

**Execution:**
1. Start `BatteryMonitor.ps1` with drill trigger level
2. Disconnect AC power
3. Allow full shutdown sequence to complete
4. Reconnect AC power
5. Power on laptop
6. Start VMware Workstation
7. Power on ESXi Master VM
8. Wait for auto-startup sequence
9. Verify all VMs online
10. Check for data corruption or issues

**Validation Checklist:**
- [ ] All VMs shutdown gracefully (check VMware Tools logs)
- [ ] No VM corruption detected on restart
- [ ] Backup jobs resume normally
- [ ] Network connectivity restored
- [ ] Veeam databases intact
- [ ] NAS storage accessible
- [ ] vCenter inventory accurate
- [ ] K8s cluster recovered
- [ ] Application services functional

**Log Review:**
```powershell
Get-Content "C:\Scripts\ShutdownLog.txt" -Tail 100
```

**Analyze:**
- Phase completion times
- Any errors or warnings
- Fallback triggers (if any)
- Total execution time

## Log File Format

**Example Log Output:**
```
[2026-01-01 14:25:30] --- BATTERY CRITICAL: STARTING EMERGENCY SHUTDOWN ---
[2026-01-01 14:25:31] Checking Inner (WinSrv22) Veeam Server...
[2026-01-01 14:25:35]    > Remote jobs killed.
[2026-01-01 14:25:36] Checking Local (Host) Veeam Server...
[2026-01-01 14:25:38]    > Local check complete.
[2026-01-01 14:25:39] PHASE 3: Shutting down Nested Workers...
...
```

================================================================================
RELATED DOCUMENTATION
================================================================================

- [04-VM-Startup-Shutdown.md](../../01-Infrastructure-Layer/DR/04-VM-Startup-Shutdown.md) - Auto-startup sequences triggered by ESXi shutdown
- [06-Design-Decisions.md](06-Design-Decisions.md) - Why hard kill? Why 75% threshold? Why no graceful stop?
- [07-Configuration-Reference.md](07-Configuration-Reference.md) - Script paths, file locations, PowerShell requirements

Back to: [README.md](README.md)
