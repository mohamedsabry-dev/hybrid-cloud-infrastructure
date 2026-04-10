# PowerShell Scripts

Windows/VMware disaster recovery automation.

## Scripts

| File | Purpose |
|------|---------|
| `BatteryMonitor.ps1` | Monitor UPS battery and trigger shutdown |
| `EmergencyLabShutdown.ps1` | Graceful VM shutdown sequence |
| `Test-LabCreds.ps1` | Validate vCenter/ESXi credentials |
| `Test-VeeamStop.ps1` | Stop Veeam backup jobs gracefully |
| `Test-VeeamStop_HardKill.ps1` | Force-stop Veeam processes |
| `Test-VeeamStop_RemoteKill.ps1` | Remote Veeam process termination |
| `Test-VeeamVisibility.ps1` | Check Veeam job visibility |

## Emergency Shutdown Flow

1. `BatteryMonitor.ps1` detects power loss
2. Triggers `EmergencyLabShutdown.ps1`
3. Stops Veeam jobs via `Test-VeeamStop.ps1`
4. Gracefully shuts down VMs in dependency order
5. Shuts down ESXi hosts

## Requirements

- PowerCLI module
- vCenter/ESXi credentials
- Admin privileges on Windows host

## Usage

```powershell
# Test credentials
.\Test-LabCreds.ps1

# Manual emergency shutdown
.\EmergencyLabShutdown.ps1
```

## Related

- [Emergency shutdown docs](../../../docs/backup/02-emergency-shutdown.md)
- [DR failover procedures](../../../docs/failover/)
