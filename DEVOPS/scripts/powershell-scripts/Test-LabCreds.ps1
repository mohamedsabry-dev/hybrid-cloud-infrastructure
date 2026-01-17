# --- CONFIGURATION (Must match your Shutdown Script) ---
$InnerCredPath   = "C:\Scripts\InnerWindowsCreds.xml" 
$vCenterCredPath = "C:\Scripts\vCenterCreds.xml"

$InnerVeeamIP    = "10.0.20.195"  # Inner Windows Server
$vCenterIP       = "10.0.20.89"   # vCenter Server

# --- TEST 1: CHECKING FILES ---
Write-Host "1. Checking Credential Files on Disk..." -NoNewline
if ((Test-Path $InnerCredPath) -and (Test-Path $vCenterCredPath)) {
    Write-Host " FOUND." -ForegroundColor Green
    $InnerCreds   = Import-Clixml -Path $InnerCredPath
    $vCenterCreds = Import-Clixml -Path $vCenterCredPath
} else {
    Write-Host " MISSING!" -ForegroundColor Red
    Write-Host "   > Stop! You need to generate the XML files first."
    exit
}

# --- TEST 2: INNER WINDOWS SERVER (Veeam) ---
Write-Host "2. Testing Login to Inner Windows Server ($InnerVeeamIP)..." -NoNewline
try {
    # Attempt to run a harmless command 'hostname' remotely
    $Result = Invoke-Command -ComputerName $InnerVeeamIP -Credential $InnerCreds -ScriptBlock { hostname } -ErrorAction Stop
    Write-Host " SUCCESS!" -ForegroundColor Green
    Write-Host "   > Connected as user: $($InnerCreds.UserName)" -ForegroundColor Gray
    Write-Host "   > Hostname returned: $Result" -ForegroundColor Gray
}
catch {
    Write-Host " FAILED!" -ForegroundColor Red
    Write-Host "   > ERROR: $($_.Exception.Message)"
    Write-Host "   > TIP: Check if 'InnerWindowsCreds.xml' has the correct password."
}

# --- TEST 3: vCENTER SERVER ---
Write-Host "3. Testing Login to vCenter ($vCenterIP)..." -NoNewline
try {
    # Configure PowerCLI to ignore SSL Certificate warnings (Crucial for scripts)
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session | Out-Null
    
    # Attempt connection
    $Session = Connect-VIServer -Server $vCenterIP -Credential $vCenterCreds -ErrorAction Stop
    Write-Host " SUCCESS!" -ForegroundColor Green
    Write-Host "   > Connected as user: $($vCenterCreds.UserName)" -ForegroundColor Gray
    Write-Host "   > vCenter Version:   $($Session.Version)" -ForegroundColor Gray
    
    # Disconnect neatly
    Disconnect-VIServer -Server $vCenterIP -Confirm:$false | Out-Null
}
catch {
    Write-Host " FAILED!" -ForegroundColor Red
    Write-Host "   > ERROR: $($_.Exception.Message)"
    Write-Host "   > TIP: Check if 'vCenterCreds.xml' uses administrator@vsphere.local"
}

Write-Host "--- TEST COMPLETE ---"