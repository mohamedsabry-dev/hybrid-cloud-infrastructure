================================================================================
CASE: ESXi Network Failure After Windows Host Sleep
================================================================================
Category: Platform - Windows Host Power Management
Severity: High
Date: Runtime Operations
Environment: Windows Host, VMware Workstation, ESXi on Bridged Network
Issue: "Uplink Down" errors and VM connectivity loss after laptop sleep

================================================================================
SYMPTOM
================================================================================
- After Windows host wakes from sleep, ESXi shows "Uplink Down" errors
- vCenter becomes unresponsive or shows disconnected hosts
- VMs lose network connectivity
- Cannot ping ESXi or VMs from Windows host
- VMware Workstation shows VMs as "running" but networking is broken
- NTP time drift on VMs (clock desynced after wake)

Visual Indicators:
- ESXi Web UI: vSwitch shows "Link Status: Down"
- vCenter: Hosts show "Not Responding" or "Disconnected"
- Windows Network Adapters: May show "Limited Connectivity"

================================================================================
ROOT CAUSE
================================================================================
When Windows laptop enters sleep mode, the network adapter is powered down
to save battery. Upon wake, the adapter reinitializes, which causes:

1. MAC Table Reset
   - Wi-Fi/Ethernet adapter clears its MAC address table
   - VMware bridge loses connection to physical adapter
   - Bridged VMs (ESXi) lose uplink connectivity

2. DHCP Lease Issues
   - Physical adapter may receive new IP address after wake
   - ESXi bridge references old adapter state
   - Network stack doesn't automatically re-bridge

3. Time Synchronization Problems
   - VMs may sync time from Windows host (if VMware Tools time sync enabled)
   - Sleep duration causes time gap
   - NTP fails if network is down during wake period

Technical Flow of Failure:
1. Windows enters sleep
2. Network adapter powered down
3. VMware bridge loses physical adapter connection
4. VMs continue running (paused or suspended)
5. Windows wakes
6. Network adapter reinitializes with fresh state
7. VMware bridge references stale adapter handle
8. ESXi shows uplink down
9. VMs have no network connectivity

================================================================================
ROOT CAUSE ANALYSIS BY COMPONENT
================================================================================

Component: Windows Power Management
------------------------------------
Default Windows behavior:
- "Allow computer to turn off this device to save power" enabled
- Aggressive sleep timers (15 minutes default)
- Network adapter treated as power-savings opportunity

Component: VMware Workstation Bridge
-------------------------------------
Bridged networking depends on continuous adapter availability:
- Bridge binds to physical adapter at VM startup
- Adapter state change breaks binding
- No automatic re-binding on wake

Component: ESXi Virtual NICs
-----------------------------
ESXi expects stable uplink:
- Monitors uplink status continuously
- Detects adapter down event
- Marks vSwitch uplink as down
- Does not automatically recover when adapter returns

================================================================================
DIAGNOSTIC PROCEDURES
================================================================================

Diagnosis 1: Verify Power Management Settings
----------------------------------------------
# Check network adapter power management
Get-NetAdapter | Get-NetAdapterPowerManagement | Select-Object Name, AllowComputerToTurnOffDevice

Problematic output:
Name     AllowComputerToTurnOffDevice
----     ----------------------------
Wi-Fi    True                          ← Problem
Ethernet True                          ← Problem

Diagnosis 2: Check Sleep Timer Configuration
---------------------------------------------
Navigate to: Settings > System > Power > Screen and sleep

Problematic settings:
- "When plugged in, put device to sleep after": 15 minutes (or any value)
- "When on battery, put device to sleep after": 5 minutes (or any value)

Diagnosis 3: Verify ESXi Uplink Status After Wake
--------------------------------------------------
SSH to ESXi (if accessible):
esxcli network vswitch standard list

Look for:
  Uplinks: vmnic0 (may show as down)

Or check via ESXi Web UI:
Networking > Virtual switches > vSwitch0 > Uplinks
Status: Down (Red) ← Problem

Diagnosis 4: Check VMware Workstation Bridge Status
----------------------------------------------------
Open VMware Workstation:
Edit > Virtual Network Editor

Check Bridged Network:
- VMnet0 should be "Bridged to" your physical adapter
- If "Automatic" or wrong adapter selected, binding may be stale

Diagnosis 5: Test Connectivity After Wake
------------------------------------------
# From Windows host
ping <GATEWAY_IP>00 (ESXi IP)
# If fails, bridge is broken

# From ESXi (if accessible via console)
vmkping <GATEWAY_IP> (gateway)
# If fails, uplink is down

================================================================================
SOLUTION
================================================================================

Solution 1: Disable Sleep While Lab is Running
-----------------------------------------------
Navigate to: Settings > System > Power > Screen and sleep

Configure:
- "When plugged in, put my device to sleep after": Never
- "When on battery, put my device to sleep after": Never (or 5 hours)
- "When plugged in, turn off screen after": Never (or 30 minutes)

Alternative PowerShell Method:
powercfg /change standby-timeout-ac 0     # Never sleep when plugged in
powercfg /change standby-timeout-dc 300   # 5 hours on battery

Solution 2: Disable Network Adapter Power Management
-----------------------------------------------------
GUI Method:
1. Open Device Manager (devmgmt.msc)
2. Expand "Network Adapters"
3. Right-click primary adapter (Wi-Fi or Ethernet) > Properties
4. Navigate to "Power Management" tab
5. UNCHECK: "Allow the computer to turn off this device to save power"
6. Click OK

PowerShell Verification:
Get-NetAdapter | Get-NetAdapterPowerManagement | Select-Object Name, AllowComputerToTurnOffDevice

Expected output after fix:
Name     AllowComputerToTurnOffDevice
----     ----------------------------
Wi-Fi    False                         ✓
Ethernet False                         ✓

Solution 3: Restart VMware Services After Wake (Recovery)
----------------------------------------------------------
If sleep already occurred and network is broken:

# Stop VMware services
net stop "VMware Authorization Service"
net stop "VMware DHCP Service"
net stop "VMware NAT Service"

# Start VMware services
net start "VMware Authorization Service"
net start "VMware DHCP Service"
net start "VMware NAT Service"

# Restart ESXi VM in VMware Workstation
# Or reconnect network adapters

Solution 4: Disable VMware Tools Time Sync
-------------------------------------------
Prevents time drift issues (use NTP hierarchy instead):

In ESXi Web UI for each VM:
1. Right-click VM > Edit Settings
2. VM Options > VMware Tools
3. Uncheck "Synchronize guest time with host"

Or via SSH:
# Disable time sync for all VMs
for vm in $(vim-cmd vmsvc/getallvms | grep -v Vmid | awk '{print $1}'); do
  vim-cmd vmsvc/message $vm tools.synctime.disable
done

Configure VMs to use NTP instead:
- IPA server syncs with internet NTP
- All VMs sync with IPA NTP server
- Hierarchical time synchronization

================================================================================
VERIFICATION
================================================================================

Verification 1: Power Settings
-------------------------------
# Sleep should be disabled or set to long timeout
powercfg /query | findstr /i "sleep"

Look for:
AC Standby Timeout: 0 (Never)

Verification 2: Network Adapter Power Management
-------------------------------------------------
Get-NetAdapter | Get-NetAdapterPowerManagement | Where-Object AllowComputerToTurnOffDevice -eq $true

Expected: No results (all adapters have power management disabled)

Verification 3: Test Sleep/Wake Cycle
--------------------------------------
1. Verify all VMs have network connectivity
2. Put Windows to sleep manually (Start > Sleep)
3. Wait 2 minutes
4. Wake Windows
5. Immediately test connectivity:
   ping <GATEWAY_IP>00
   ping <GATEWAY_IP>01

Expected: All pings succeed immediately after wake

Verification 4: ESXi Uplink Status After Wake
----------------------------------------------
SSH to ESXi after wake:
esxcli network vswitch standard list

Verify:
Uplinks: vmnic0
Status: Up (should NOT show down)

================================================================================
PREVENTION
================================================================================
1. Configure power settings BEFORE deploying lab infrastructure
2. Document power configuration in pre-flight checklist
3. Test sleep/wake cycle before building complex environments
4. Use NTP hierarchy instead of VMware Tools time sync
5. Create monitoring alert for ESXi uplink down events
6. Consider dedicated lab machine that never sleeps
7. Use laptop only when actively working in lab (shutdown when done)

Pre-Flight Checklist Items:
□ Sleep disabled or set to long timeout (5+ hours)
□ Network adapter power management disabled
□ Screen timeout configured (can stay on)
□ VMware Tools time sync disabled
□ NTP configured for VMs

================================================================================
WORKAROUNDS FOR MOBILE LAB USE
================================================================================

If you need sleep functionality for mobile lab:

Workaround 1: Graceful Shutdown Before Sleep
---------------------------------------------
Before closing laptop:
1. Shutdown all VMs gracefully
2. Shutdown ESXi Master
3. Close VMware Workstation
4. Put Windows to sleep

On wake:
1. Start VMware Workstation
2. Power on ESXi Master
3. Wait for ESXi to fully boot
4. Power on VMs

Workaround 2: Hibernate Instead of Sleep
-----------------------------------------
Hibernate saves full state to disk:
- More reliable recovery than sleep
- Network adapters reinitialize properly
- VMs may still need restart

Configure hibernate:
powercfg /hibernate on

Use hibernate instead of sleep when mobile

Workaround 3: Suspend VMs, Not Windows
---------------------------------------
VMware Workstation can suspend VMs:
1. Suspend all VMs (VM > Power > Suspend)
2. Keep Windows running (don't sleep)
3. VMs resume with network intact

Note: Windows still needs power (no battery savings)

================================================================================
IMPACT ANALYSIS
================================================================================

Home Lab Impact: High
---------------------
- Lost connectivity during troubleshooting sessions
- Time wasted diagnosing "network issues" (actually power management)
- Risk of VM corruption if databases/services timeout during network outage
- NTP drift causes authentication failures (Kerberos time-sensitive)

Production Impact: N/A
----------------------
- Servers don't sleep
- Dedicated hardware doesn't have power management issues
- Lesson: Lab on laptop has unique constraints

================================================================================
REFERENCES
================================================================================
Source: /DC-K8s/.archive/00-HOST-FOUNDATION/02-windows-host-configuration.md
Related Cases:
  - 07-Windows-Host-Network-Loops.txt (IP forwarding issues)
Related Docs: Windows Host Pre-Flight Configuration

================================================================================
LESSONS LEARNED
================================================================================
- Laptop power management conflicts with 24/7 lab services
- Sleep breaks network bridges at multiple layers
- Windows defaults prioritize battery over infrastructure stability
- Time synchronization requires network stability
- Mobile lab requires different workflows than fixed lab
- "Uplink Down" errors can be caused by host power management, not network issues
- Always test sleep/wake before assuming lab will survive it
- Consider dedicated hardware for labs that need 24/7 uptime
- Pre-flight configuration prevents mysterious runtime failures
- Document power management in infrastructure prerequisites
