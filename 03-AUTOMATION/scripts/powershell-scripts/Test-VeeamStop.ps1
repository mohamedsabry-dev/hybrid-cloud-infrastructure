# TEST SCRIPT: DETECT SESSIONS -> MATCH JOB -> STOP (Fixed Logic)
# REQUIRES: PowerShell 7 (pwsh)

Write-Host "--- VEEAM KILL SWITCH (FIXED V2) ---" -ForegroundColor Cyan

try {
    Write-Host "1. Loading Veeam v13 Module..." -NoNewline
    Import-Module Veeam.Backup.PowerShell -ErrorAction Stop
    Write-Host " DONE." -ForegroundColor Green

    # 1. FIND THE ACTIVE SESSION
    Write-Host "2. Scanning for Active Sessions..." -NoNewline
    $ActiveSessions = Get-VBRBackupSession | Where-Object {$_.State -eq 'Working'}

    if ($ActiveSessions) {
        Write-Host " FOUND!" -ForegroundColor Red
        foreach ($session in $ActiveSessions) {
            Write-Host "   > TARGET LOCKED: '$($session.Name)'" -ForegroundColor Yellow
            
            # 2. FIND THE MATCHING JOB (The Fix)
            # Since Get-VBRJob -Id doesn't exist, we must search for it manually.
            $JobToKill = Get-VBRJob | Where-Object { $_.Id -eq $session.JobId }
            
            if ($JobToKill) {
                # 3. KILL THE JOB
                Write-Host "   > Identified Parent Job: '$($JobToKill.Name)'" -ForegroundColor Gray
                Write-Host "   > Sending STOP signal..." -NoNewline
                Stop-VBRJob -Job $JobToKill -Gracefully
                Write-Host " SENT." -ForegroundColor Green
            } else {
                Write-Host "   > ERROR: Could not find the parent job object!" -ForegroundColor Red
            }
        }

        # 4. VERIFY IT WORKED
        Write-Host "3. Verifying..."
        for ($i=1; $i -le 10; $i++) {
            Start-Sleep -Seconds 3
            # Check if the session is still 'Working'
            $Check = Get-VBRBackupSession | Where-Object {$_.Id -eq $ActiveSessions.Id}
            
            if (-not $Check -or $Check.State -ne 'Working') {
                Write-Host "   SUCCESS: Job is stopping/stopped." -ForegroundColor Green
                break
            }
            Write-Host "   ... waiting for stop ..." -ForegroundColor Gray
        }

    } else {
        Write-Host " NONE." -ForegroundColor Yellow
        Write-Host "   > No active sessions found. (Start the job again!)"
    }

} catch {
    Write-Host " ERROR!" -ForegroundColor Red
    Write-Host "   > $($_.Exception.Message)"
}