# TEST SCRIPT: REMOTE HARD KILL (Inner Server)
# TARGET: Windows Server 2022 (10.0.20.195)

$InnerVeeamIP  = "10.0.20.195"
$InnerCredPath = "C:\Scripts\InnerWindowsCreds.xml"

Write-Host "--- REMOTE VEEAM HARD KILL TEST ---" -ForegroundColor Cyan

# 1. Load Credentials
if (Test-Path $InnerCredPath) {
    $InnerCreds = Import-Clixml -Path $InnerCredPath
} else {
    Write-Host "ERROR: Credential file missing." -ForegroundColor Red; exit
}

# 2. Execute Remote Kill
try {
    Write-Host "Connecting to $InnerVeeamIP..." -NoNewline
    
    # We send the command to the server
    $Result = Invoke-Command -ComputerName $InnerVeeamIP -Credential $InnerCreds -ScriptBlock {
        
        # We force a nested PowerShell 7 session inside the server
        # This is required for Veeam v13 modules
        $InnerLog = pwsh -Command {
            Write-Output "   [Remote] Loading Veeam Module..."
            Import-Module Veeam.Backup.PowerShell -ErrorAction SilentlyContinue
            
            # Find Active Sessions
            $Sessions = Get-VBRBackupSession | Where-Object {$_.State -eq 'Working'}
            
            if ($Sessions) {
                foreach ($s in $Sessions) {
                    Write-Output "   [Remote] TARGET LOCKED: $($s.Name)"
                    
                    # Find Parent Job
                    $Job = Get-VBRJob | Where-Object { $_.Id -eq $s.JobId }
                    
                    if ($Job) {
                        Write-Output "   [Remote] Killing Job: $($Job.Name)..."
                        # HARD KILL (No Graceful flag)
                        Stop-VBRJob -Job $Job 
                        Write-Output "   [Remote] KILL SIGNAL SENT."
                    }
                }
                return "SUCCESS"
            } else {
                return "NO_JOBS"
            }
        }
        return $InnerLog

    } -ErrorAction Stop

    # 3. Analyze Results
    Write-Host " CONNECTED." -ForegroundColor Green
    
    if ($Result -match "SUCCESS") {
        Write-Host "RESULTS:" -ForegroundColor Green
        $Result | ForEach-Object { Write-Host $_ }
        Write-Host "`n>>> TEST PASSED: Remote job was killed." -ForegroundColor Cyan
    } 
    elseif ($Result -match "NO_JOBS") {
        Write-Host "RESULTS: No active jobs found." -ForegroundColor Yellow
        Write-Host ">>> TEST INCOMPLETE: Did you start a backup job inside the VM?" -ForegroundColor Yellow
    }
    else {
        Write-Host "RESULTS: Unexpected output." 
        $Result | ForEach-Object { Write-Host $_ }
    }

} catch {
    Write-Host " FAILED!" -ForegroundColor Red
    Write-Host "   > ERROR: $($_.Exception.Message)"
}