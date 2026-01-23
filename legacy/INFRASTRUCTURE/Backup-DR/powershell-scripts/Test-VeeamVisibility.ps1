# --- CONFIGURATION ---
$InnerCredPath = "C:\Scripts\InnerWindowsCreds.xml" 
$InnerVeeamIP  = "10.0.20.195"

Write-Host "--- VEEAM v13 SENSOR TEST (PS7 EDITION) ---" -ForegroundColor Cyan

# 1. TEST LOCAL VEEAM (Host)
# This part assumes you are running THIS script inside the new PowerShell 7 console!
Write-Host "1. Checking LOCAL Veeam..." -NoNewline
try {
    # Check if we are in the right PowerShell
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Host " FAILED!" -ForegroundColor Red
        Write-Host "   > ERROR: You are running this in the old Blue PowerShell."
        exit
    }

    # Load the Modern v13 Module
    Import-Module Veeam.Backup.PowerShell -ErrorAction Stop
    $LocalJobs = Get-VBRJob
    
    if ($LocalJobs) {
        Write-Host " SUCCESS!" -ForegroundColor Green
        Write-Host "   > Found: $($LocalJobs.Name)" -ForegroundColor Gray
    } else {
        Write-Host " SUCCESS (No Jobs)." -ForegroundColor Yellow
    }
}
catch {
    Write-Host " FAILED!" -ForegroundColor Red
    Write-Host "   > ERROR: $($_.Exception.Message)"
}

# 2. TEST REMOTE VEEAM (Inner Lab)
Write-Host "`n2. Checking REMOTE Veeam..." -NoNewline
if (Test-Path $InnerCredPath) { $InnerCreds = Import-Clixml -Path $InnerCredPath }

try {
    # TRICK: We use 'pwsh' inside the remote command to force PowerShell 7 environment
    Invoke-Command -ComputerName $InnerVeeamIP -Credential $InnerCreds -ScriptBlock {
        
        # We launch a nested PowerShell 7 process to bypass the default 5.1 shell
        $Result = pwsh -Command {
            Import-Module Veeam.Backup.PowerShell -ErrorAction Stop
            $J = Get-VBRJob
            if ($J) { return $J.Name } else { return "NoJobsFound" }
        }
        return $Result

    } -ErrorAction Stop
    
    Write-Host " SUCCESS!" -ForegroundColor Green
}
catch {
    Write-Host " FAILED!" -ForegroundColor Red
    Write-Host "   > ERROR: $($_.Exception.Message)"
}