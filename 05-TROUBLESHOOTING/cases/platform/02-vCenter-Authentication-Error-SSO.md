================================================================================
CASE: vCenter Authentication Error - SSO Alias Rejection
================================================================================
Category: Platform - vCenter SSO/Authentication
Severity: Medium
Date: Post-Installation
Environment: vCenter 8.0.3, ESXi 8.0
Error: "An Error Occurred During Authentication"

================================================================================
SYMPTOM
================================================================================
- After successful installation, accessing https://vsphere.local shows authentication error
- Correct credentials (administrator@vsphere.local) are rejected
- Same credentials work when accessing via IP address (https://192.168.0.101)
- Error appears even with valid admin password

Visual Error:
![Auth Error](https://github.com/user-attachments/assets/7dcd5123-cf67-4da8-a49c-1f2982595397)

================================================================================
ROOT CAUSE
================================================================================
vCenter's SSO (Single Sign-On) service only trusts its configured FQDN or IP
address by default. Accessing via aliases like "vsphere" (without ".local")
triggers authentication rejection by the SSO service provider.

The SSO whitelist does not include hostname variations, causing the service to
reject authentication attempts from non-whitelisted aliases.

================================================================================
TECHNICAL ANALYSIS
================================================================================
SSO Service Provider Security Model:
- Maintains whitelist of trusted hostnames/aliases
- Validates authentication requests against whitelist
- Rejects requests from non-whitelisted sources (even if credentials are valid)
- Default whitelist includes: configured FQDN and IP address only

Configuration File: /etc/vmware/vsphere-ui/webclient.properties
Key Setting: sso.serviceprovider.alias.whitelist

================================================================================
SOLUTION: Whitelist SSO Alias
================================================================================

Step 1: SSH into vCenter
-------------------------
ssh root@192.168.0.101

Step 2: Enable Shell
---------------------
shell

Step 3: Stop vSphere UI Service
--------------------------------
service-control --stop vsphere-ui

Step 4: Navigate to Config Directory & Backup
----------------------------------------------
cd /etc/vmware/vsphere-ui/
cp webclient.properties /var/tmp/webclient.properties.bak

Step 5: Edit Configuration
---------------------------
vi webclient.properties

In VI Editor:
1. Press / to search
2. Type: sso.serviceprovider.alias.whitelist
3. Press Enter to find the line
4. Press i to enter Insert mode
5. Remove # to uncomment the line
6. Edit to: sso.serviceprovider.alias.whitelist=vsphere,vsphere.local,vcapp
7. Press Esc to exit Insert mode
8. Type :wq! and press Enter to save and quit

Step 6: Restart Service
------------------------
service-control --start vsphere-ui

Visual Reference:
![Service Control](https://github.com/user-attachments/assets/4d166c5a-9539-47d9-bec0-7b4da0acb9ec)

Step 7: Verify Service Started
-------------------------------
service-control --status vsphere-ui

Wait 2-3 minutes for service to fully initialize.

================================================================================
VERIFICATION
================================================================================
After applying fix, you can access vCenter via any whitelisted alias:
- https://vsphere.local ✓
- https://vsphere ✓
- https://192.168.0.101 ✓

Test each URL to confirm authentication works.

================================================================================
PREVENTION
================================================================================
1. Configure SSO alias whitelist during initial setup
2. Include all hostname variations you plan to use
3. Document whitelisted aliases in infrastructure documentation
4. Test authentication via all planned access methods after installation

================================================================================
ALTERNATIVE APPROACHES
================================================================================
Option 1: Use only FQDN
- Simplest approach
- No configuration needed
- Limits flexibility

Option 2: Configure DNS CNAMEs
- Create DNS aliases pointing to vsphere.local
- Requires DNS server access
- More complex but more robust

Option 3: Whitelist multiple aliases
- Most flexible approach (implemented in solution)
- Allows short names, FQDNs, and IPs
- Requires service restart

================================================================================
REFERENCES
================================================================================
Source: /DC-K8s/.archive/00-HOST-FOUNDATION/01-vcenter/05-troubleshooting.md
Related Cases: 01-vCenter-Installation-Stage2-Hang (DNS configuration)
Related Files: /etc/vmware/vsphere-ui/webclient.properties

================================================================================
LESSONS LEARNED
================================================================================
- SSO security is strict by design - not a bug
- Always backup configuration files before editing
- Service restarts can take 2-3 minutes - be patient
- Test all access methods after configuration changes
- Hostname aliases need explicit whitelisting for SSO
