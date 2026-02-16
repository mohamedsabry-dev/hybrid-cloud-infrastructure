================================================================================
CASE: vSphere Lifecycle Manager Plugin Download Error
================================================================================
Category: Platform - vCenter Plugin Management
Severity: Medium
Date: Post-IP/Certificate Change
Environment: vCenter 8.0.3
Error: "Error downloading plug-in. URL is unreachable"

================================================================================
SYMPTOM
================================================================================
- vSphere Client shows plugin download error for Lifecycle Manager
- Error in Administration > Client Plugins section
- Error message: "Error downloading plug-in. URL is unreachable"
- Detailed errors include:
  * TlsFatalAlert: unexpected_message(10); Unsupported UNKNOWN(72)
  * Status code: 503, reason phrase: Service Unavailable
  * ssl_connect error 1
- Issue appears after vCenter IP change (192.168.0.101 → 10.0.20.89)
- Issue appears after certificate regeneration

Plugin Details:
- Name: VMware vSphere Lifecycle Manager Client
- ID: com.vmware.vlcm.client:8.0.3.24322831
- Expected URL: https://vcenter.home.lab:9087/vci/downloads/vlcm-ui/plugin.zip

================================================================================
ROOT CAUSE
================================================================================
Multiple interconnected issues after IP/hostname change:

1. Extension Registry References Old IP:
   - vCenter Extension Manager still has old IP (192.168.0.101) registered
   - Plugin download attempts to contact non-existent old IP

2. Hostname Resolution to Localhost:
   - vCenter /etc/hosts file resolves vcenter.home.lab to 127.0.0.1 (IPv6: ::1)
   - Update Manager service listens on physical IP (10.0.20.89), not localhost
   - Internal download requests fail because service unreachable on loopback

3. Services Disabled:
   - vmware-updatemgr service may be disabled/stopped to save RAM
   - vmware-vlm service may be disabled/stopped
   - Plugin download fails when source service is not running

================================================================================
TECHNICAL ANALYSIS
================================================================================
vCenter Extension Architecture:
- Extensions register download URLs in Extension Manager
- URLs stored with specific IP/hostname at registration time
- vSphere Client uses these URLs to download plugin files
- No automatic update when IP/hostname changes

Service Dependencies:
- vmware-updatemgr: Provides plugin files on ports 9084 (HTTP) and 9087 (HTTPS)
- vmware-vlm: Lifecycle Manager service
- vsphere-ui: Client interface that downloads plugins

Port Configuration:
- Port 9084: HTTP (insecure) - Internal use
- Port 9087: HTTPS (secure) - Client plugin downloads
- Config file: /usr/lib/vmware-updatemgr/bin/vci-integrity.xml

Hostname Resolution Priority:
- /etc/hosts checked first before DNS
- IPv6 (::1) takes precedence over IPv4 if hostname listed on both
- VAMI service auto-generates /etc/hosts content

Log Locations:
- /var/log/vmware/vmware-updatemgr/vum-server.log
- /var/log/vmware/vsphere-ui/logs/vsphere_client_virgo.log

================================================================================
SOLUTION: Multi-Step Resolution
================================================================================

PHASE 1: Fix Hostname Resolution (Critical)
--------------------------------------------
The vCenter server must resolve its own hostname to the real IP, not localhost.

Step 1.1: SSH to vCenter
ssh root@vcenter.home.lab

Step 1.2: Check Current Resolution
ping -c 3 vcenter.home.lab

If it shows 127.0.0.1 or ::1, proceed to fix:

Step 1.3: Edit /etc/hosts
vi /etc/hosts

Find the line:
::1  vcenter.home.lab vcenter localhost ipv6-localhost ipv6-loopback

Change to (remove vcenter.home.lab and vcenter from IPv6 line):
::1  localhost ipv6-localhost ipv6-loopback

Ensure this line exists:
10.0.20.89 vcenter.home.lab vcenter

Save and exit (:wq)

Step 1.4: Verify Fix
ping -c 3 vcenter.home.lab

Should now show: PING vcenter.home.lab (10.0.20.89)...

PHASE 2: Enable Required Services
----------------------------------
Step 2.1: Check Service Status
service-control --status vmware-updatemgr
service-control --status vmware-vlm

Step 2.2: Set Services to Automatic Start
/bin/vmon-cli --update vmware-updatemgr --starttype AUTOMATIC
/bin/vmon-cli --update vmware-vlm --starttype AUTOMATIC

Step 2.3: Start Services
service-control --start vmware-updatemgr
service-control --start vmware-vlm

Wait 3-5 minutes for services to fully initialize.

PHASE 3: Reset Plugin Extension
--------------------------------
Step 3.1: Access Managed Object Browser (MOB)
https://vcenter.home.lab/mob/?moid=ExtensionManager&method=unregisterExtension

Login with administrator@vsphere.local

Step 3.2: Unregister Old Extension
In extensionKey box: com.vmware.vlcm.client
Click: Invoke Method
Result: void

Step 3.3: Restart Update Manager
service-control --restart vmware-updatemgr

Wait 3-5 minutes. Service will auto-register with new IP.

PHASE 4: Clear Client Cache
----------------------------
Step 4.1: Restart vSphere UI Service
service-control --restart vsphere-ui

Warning: This disconnects web console for 5-10 minutes.

Step 4.2: Wait for Service Initialization
Monitor with: service-control --status vsphere-ui
Wait until status shows RUNNING.

================================================================================
VERIFICATION
================================================================================
Step 1: Verify Plugin Download URL
-----------------------------------
Browser: https://vcenter.home.lab:9087/vci/downloads/vlcm-ui/plugin.zip
Should: Download plugin.zip file successfully

Step 2: Check MOB Extension URL
--------------------------------
MOB: ExtensionManager > FindExtension > com.vmware.vlcm.client
Verify URL shows: https://vcenter.home.lab:9087/... (not old IP)

Step 3: Check Client Plugins
-----------------------------
vSphere Client: Administration > Client Plugins
Status should show:
- Download plug-in: Completed (green checkmark)
- Deploy plug-in: Completed (green checkmark)
- Overall Status: Deployed/Enabled

Step 4: Access Lifecycle Manager
---------------------------------
Menu > Lifecycle Manager
Should: Load dashboard without errors

================================================================================
PREVENTION
================================================================================
1. After IP/hostname changes, always verify /etc/hosts resolution
2. Never put FQDN on the ::1 (IPv6 localhost) line
3. Keep service states documented if disabling to save RAM
4. Reset extensions after certificate changes: unregister + restart services
5. Test plugin downloads immediately after infrastructure changes
6. Maintain service startup configuration documentation

Hostname Resolution Best Practice:
```
127.0.0.1  localhost
::1        localhost ipv6-localhost ipv6-loopback
10.0.20.89 vcenter.home.lab vcenter
```

Note: The VAMI service may regenerate /etc/hosts - check after reboots.

================================================================================
ALTERNATIVE APPROACHES
================================================================================
Option 1: Disable Lifecycle Manager (RAM Savings)
--------------------------------------------------
If not using Lifecycle Manager features:
1. Unregister extension (prevents error banner)
2. Keep services disabled
3. Save ~500MB+ RAM
4. Lose vLCM capabilities

Commands:
MOB: unregisterExtension > com.vmware.vlcm.client
Disable: /bin/vmon-cli --update vmware-updatemgr --starttype DISABLED

Option 2: Manual Extension Update (Advanced)
---------------------------------------------
Instead of unregister/restart, manually edit extension via MOB UpdateExtension.
- More complex, error-prone
- Requires perfect syntax in MOB text box
- Not recommended due to certificate blocks

Option 3: Use IP Instead of Hostname
-------------------------------------
Configure systems to use IP (10.0.20.89) instead of FQDN
- Avoids hostname resolution issues
- Loses certificate validation benefits
- Not recommended for production

================================================================================
RELATED CONFIGURATION FILES
================================================================================
/etc/hosts - Hostname resolution
/usr/lib/vmware-updatemgr/bin/vci-integrity.xml - Port configuration
/var/log/vmware/vmware-updatemgr/vum-server.log - Service logs
/var/log/vmware/vsphere-ui/logs/vsphere_client_virgo.log - Client logs

MOB Endpoints:
- ExtensionManager: /mob/?moid=ExtensionManager
- FindExtension: /mob/?moid=ExtensionManager&method=findExtension
- UnregisterExtension: /mob/?moid=ExtensionManager&method=unregisterExtension

================================================================================
TROUBLESHOOTING TIPS
================================================================================
Q: Port 9087 shows SSL errors?
A: Restart vmware-updatemgr service. It may not trust new certificates.

Q: Extension not auto-registering after restart?
A: Wait 10 minutes. If still missing, restart vsphere-ui as well.

Q: Plugin downloads in browser but fails in client?
A: Check /etc/hosts - vCenter must resolve to real IP internally.

Q: Services keep stopping?
A: Check startup type: vmon-cli --list | grep -E "updatemgr|vlm"

Q: Error persists after all steps?
A: Check certificate trust: /usr/lib/vmware-vmca/bin/certificate-manager

================================================================================
REFERENCES
================================================================================
Source: draft for 29 (lines 38-1120)
KB Article: https://knowledge.broadcom.com/external/article/407414/
Related Cases: 13-vCenter-Backup-Failure-After-IP-Change.md
Port Config: /usr/lib/vmware-updatemgr/bin/vci-integrity.xml

================================================================================
LESSONS LEARNED
================================================================================
- IP changes require extension registry updates, not automatic
- Localhost resolution (::1/127.0.0.1) breaks plugin downloads
- IPv6 takes precedence in /etc/hosts if hostname appears on multiple lines
- Service restarts can take 5-10 minutes - patience required
- VAMI may regenerate /etc/hosts - check after reboots
- Disabling services saves RAM but breaks dependent features
- MOB is powerful but syntax-sensitive for manual updates
- Always verify internal hostname resolution after network changes
- Extension cache in vsphere-ui must be cleared after backend fixes
