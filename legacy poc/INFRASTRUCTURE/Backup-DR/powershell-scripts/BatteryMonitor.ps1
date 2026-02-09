# --- CONFIGURATION ---
$TriggerPercent  = 75    # Set this to 1% below your current level for the drill
$ShutdownScript  = "C:\Scripts\EmergencyLabShutdown.ps1"
$CheckInterval   = 30     # Check every 30 seconds (Fast updates)

# --- VISUAL SETUP ---
Clear-Host
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   LIVE BATTERY MONITORING STATION" -ForegroundColor Cyan
Write-Host "   Target Trigger: $TriggerPercent%" -ForegroundColor Yellow
Write-Host "   Action: EXECUTE KILL SWITCH" -ForegroundColor Red
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# --- MAIN MONITOR LOOP ---
while ($true) {
    # 1. Get Battery Status
    $Battery = Get-CimInstance -ClassName Win32_Battery
    $Percent = $Battery.EstimatedChargeRemaining
    $Status  = $Battery.BatteryStatus # 1=Discharging, 2=AC Power

    # 2. Define Status Text
    $TimeStamp = Get-Date -Format "HH:mm:ss"
    
    if ($Status -eq 2) {
        $PowerState = "AC POWER (Safe)"
        $Color = "Green"
    } else {
        $PowerState = "DISCHARGING (Danger)"
        $Color = "Yellow"
    }

    # 3. Display Status Line
    Write-Host "[$TimeStamp] Battery: $Percent% | Mode: $PowerState" -ForegroundColor $Color

    # 4. CHECK TRIGGER CONDITION
    # Condition: Discharging AND Battery is below Limit
    if ($Status -ne 2 -and $Percent -le $TriggerPercent) {
        
        Write-Host ""
        Write-Host "----------------------------------------" -ForegroundColor Red
        Write-Host "[CRITICAL] THRESHOLD REACHED ($Percent%)" -ForegroundColor Red
        Write-Host "[CRITICAL] INITIATING EMERGENCY SHUTDOWN..." -ForegroundColor Red
        Write-Host "----------------------------------------" -ForegroundColor Red
        
        # Launch the Shutdown Script and show its output
        & $ShutdownScript
        
        # Stop monitoring after trigger
        break
    }

    # 5. Wait for next check
    Start-Sleep -Seconds $CheckInterval
}