# TEST SCRIPT: HARD KILL MODE (No Graceful Wait)
# REQUIRES: PowerShell 7 (pwsh)

Write-Host "--- VEEAM HARD KILL TEST ---" -ForegroundColor Cyan

try {
    Write-Host "1. Loading Veeam v13 Module..." -NoNewline
    Import-Module Veeam.Backup.PowerShell -ErrorAction Stop
    Write-Host " DONE." -ForegroundColor Green

    # 1. FIND SESSION
    $ActiveSessions = Get-VBRBackupSession | Where-Object {$_.State -eq 'Working'}

    if ($ActiveSessions) {
        foreach ($session in $ActiveSessions) {
            Write-Host "   > TARGET LOCKED: '$($session.Name)'" -ForegroundColor Yellow
            
            # 2. FIND JOB
            $JobToKill = Get-VBRJob | Where-Object { $_.Id -eq $session.JobId }
            
            if ($JobToKill) {
                # 3. KILL (IMMEDIATE)
                # We removed '-Gracefully'. This forces an immediate interrupt.
                Write-Host "   > Sending IMMEDIATE STOP signal..." -NoNewline
                Stop-VBRJob -Job $JobToKill 
                Write-Host " SENT." -ForegroundColor Green
            }
        }

        # 4. VERIFY
        Write-Host "3. Verifying..."
        for ($i=1; $i -le 10; $i++) {
            Start-Sleep -Seconds 2
            $Check = Get-VBRBackupSession | Where-Object {$_.Id -eq $ActiveSessions.Id}
            
            # If state is 'Stopping' or session is null, we won.
            if (-not $Check -or $Check.State -ne 'Working') {
                Write-Host "   SUCCESS: Job status is '$($Check.State)'." -ForegroundColor Green
                break
            }
            Write-Host "   ... waiting for death ..." -ForegroundColor Gray
        }
    } else {
        Write-Host "   > No active jobs to kill." -ForegroundColor Yellow
    }

} catch {
    Write-Host " ERROR: $($_.Exception.Message)" -ForegroundColor Red
}