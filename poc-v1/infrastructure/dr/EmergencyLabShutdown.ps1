# --- SELF-CORRECTION: FORCE POWERSHELL 7 ---
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "Detected old PowerShell 5. Restarting in PowerShell 7..." -ForegroundColor Yellow
    $ScriptPath = $MyInvocation.MyCommand.Definition
    Start-Process pwsh -ArgumentList "-File `"$ScriptPath`"" -Wait -NoNewWindow
    exit
}
# --- ENSURE VEEAM MODULE IS FOUND (Auto-Fix) ---
$VeeamPath = "C:\Program Files\Veeam\Backup and Replication\Console"
if (Test-Path $VeeamPath) {
    [Environment]::SetEnvironmentVariable("PSModulePath", $env:PSModulePath + ";$VeeamPath", "Machine")
}
# ------------------------------------------------

# --- CONFIGURATION ---
$LogPath         = "C:\Scripts\ShutdownLog.txt"
$InnerCredPath   = "C:\Scripts\InnerWindowsCreds.xml" 
$vCenterCredPath = "C:\Scripts\vCenterCreds.xml"

$InnerVeeamIP    = "10.0.20.195" 
$vCenterIP       = "10.0.20.89"
$NestedWorkers   = @("10.0.20.101", "10.0.20.102")
$MasterESXi      = "10.0.20.100"
# [VERIFY THIS PATH]
$MasterVMX       = "F:\ESXI_Master\ESXi_Master.vmx" 
$VmrunPath       = "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe"

Function Write-Log {
    Param ([string]$Message, [string]$Color = "White")
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogLine = "[$TimeStamp] $Message"
    Write-Host $LogLine -ForegroundColor $Color
    Add-Content -Path $LogPath -Value $LogLine
}

Write-Log "--- BATTERY CRITICAL: STARTING EMERGENCY SHUTDOWN ---" "Red"

# 1. LOAD CREDENTIALS
if ((Test-Path $InnerCredPath) -and (Test-Path $vCenterCredPath)) {
    $InnerCreds   = Import-Clixml -Path $InnerCredPath
    $vCenterCreds = Import-Clixml -Path $vCenterCredPath
} else {
    Write-Log "ERROR: Credentials missing! Halting." "Red"
    Stop-Computer; exit
}

# 2. STOP VEEAM JOBS (Hard Kill)
Function Stop-Veeam-Safe {
    Param ($Target, $IsRemote, $IP, $Creds)
    Write-Log "Checking $Target Veeam Server..." "Cyan"
    
    if ($IsRemote) {
        try {
            # Run inside pwsh to guarantee module load
            $Result = Invoke-Command -ComputerName $IP -Credential $Creds -ScriptBlock {
                $Inner = pwsh -Command {
                    Import-Module Veeam.Backup.PowerShell -ErrorAction SilentlyContinue
                    $Sessions = Get-VBRBackupSession | Where-Object {$_.State -eq 'Working'}
                    if ($Sessions) {
                        foreach ($s in $Sessions) {
                            $Job = Get-VBRJob | Where-Object { $_.Id -eq $s.JobId }
                            if ($Job) { Stop-VBRJob -Job $Job; Write-Output "Killed $($Job.Name)" }
                        }
                        return "JobsKilled"
                    }
                }
                return $Inner
            } -ErrorAction Stop

            if ($Result -match "JobsKilled") { Write-Log "   > Remote jobs killed." "Green" }
            else { Write-Log "   > No active remote jobs." "Green" }
        } catch { Write-Log "   > Could not contact Inner Veeam. Skipping." "Yellow" }
    } else {
        # Local Check (Host)
        pwsh -Command {
            Import-Module Veeam.Backup.PowerShell -ErrorAction SilentlyContinue
            $Sessions = Get-VBRBackupSession | Where-Object {$_.State -eq 'Working'}
            if ($Sessions) {
                 foreach ($s in $Sessions) {
                    $Job = Get-VBRJob | Where-Object { $_.Id -eq $s.JobId }
                    if ($Job) { Stop-VBRJob -Job $Job }
                 }
            }
        }
        Write-Log "   > Local check complete." "Green"
    }
}

Stop-Veeam-Safe -Target "Inner (WinSrv22)" -IsRemote $true -IP $InnerVeeamIP -Creds $InnerCreds
Stop-Veeam-Safe -Target "Local (Host)" -IsRemote $false


# 3. SHUTDOWN WORKERS (101, 102)
Write-Log "PHASE 3: Shutting down Nested Workers..." "Cyan"

try {
    Connect-VIServer -Server $vCenterIP -Credential $vCenterCreds -ErrorAction Stop | Out-Null
    
    # Send Signal
    foreach ($hostIP in $NestedWorkers) {
        Write-Log "   > Sending Shutdown Signal to $hostIP..."
        # -Force is REQUIRED to bypass "Maintenance Mode" check. It triggers standard shutdown.
        Stop-VMHost -VMHost $hostIP -Force -Confirm:$false -ErrorAction SilentlyContinue
    }
    
    # WAIT 4 MINUTES
    Write-Log "   > Waiting 3 minutes for Workers to die..." "Yellow"
    $Timer = 0
    $MaxWait = 180 
    do {
        Start-Sleep -Seconds 10
        $Timer += 10
        $Alive = Test-Connection -ComputerName $NestedWorkers -Count 1 -Quiet -ErrorAction SilentlyContinue
        Write-Log "     ... waiting ($Timer / $MaxWait sec)" "Gray"
    } while ($Alive -and $Timer -lt $MaxWait)

    if ($Alive) { Write-Log "WARNING: Workers still pingable. Proceeding anyway." "Red" }
    else { Write-Log "SUCCESS: Workers are down." "Green" }

} catch {
    Write-Log "CRITICAL: vCenter Unreachable. Skipping to Host Shutdown." "Red"
}


# 4. SHUTDOWN MASTER (100)
Write-Log "PHASE 4: Shutting down Master ESXi ($MasterESXi)..." "Cyan"
try {
    Write-Log "   > Sending Shutdown Signal to Master..."
    # -Force is REQUIRED to bypass "Maintenance Mode" check.
    Stop-VMHost -VMHost $MasterESXi -Force -Confirm:$false -ErrorAction SilentlyContinue
    
    # WAIT 4 MINUTES
    Write-Log "   > Waiting 3 minutes for Master to die..." "Yellow"
    $Timer = 0
    $MaxWait = 180 
    do {
        Start-Sleep -Seconds 10
        $Timer += 10
        $MasterAlive = Test-Connection -ComputerName $MasterESXi -Count 1 -Quiet
        Write-Log "     ... waiting ($Timer / $MaxWait sec)" "Gray"
    } while ($MasterAlive -eq $true -and $Timer -lt $MaxWait)

} catch {
    Write-Log "ERROR: Could not stop Master via vCenter." "Red"
    $MasterAlive = $true 
}


# 5. WORKSTATION FALLBACK (Outer Layer)
if ($MasterAlive) {
    Write-Log "PHASE 5: Master still up. Attempting Workstation Soft Stop..." "Red"
    
    if (Test-Path $VmrunPath) {
        # "soft" = Pressing Power Button in VMware Workstation
        Start-Process -FilePath $VmrunPath -ArgumentList "-T ws stop `"$MasterVMX`" soft" -Wait -NoNewWindow
        
        # WAIT 3 MINUTES
        Write-Log "   > Waiting 3 minutes for Workstation Soft Stop..." "Yellow"
        Start-Sleep -Seconds 180
    } else {
        Write-Log "   > ERROR: vmrun.exe not found. Skipping Soft Stop." "Red"
    }
}

# FINAL CHECK & HARD KILL
$FinalCheck = Test-Connection -ComputerName $MasterESXi -Count 1 -Quiet
if ($FinalCheck) {
    Write-Log "TIMEOUT: Master refused to die. EXECUTING HARD KILL." "Red"
    Stop-Process -Name "vmware-vmx" -Force -ErrorAction SilentlyContinue
    Write-Log "   > Buffer: Waiting 2 minutes..." "Yellow"
    Start-Sleep -Seconds 120
} else {
    Write-Log "SUCCESS: Lab is silent." "Green"
}


# 6. SHUTDOWN LAPTOP
Write-Log "PHASE 6: Goodnight." "Cyan"
Stop-Computer