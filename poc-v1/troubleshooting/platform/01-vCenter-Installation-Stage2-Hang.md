================================================================================
CASE: vCenter Installation Stuck at Stage 2 (0% Progress)
================================================================================
Category: Platform - vCenter Installation
Severity: High
Date: Initial Setup Phase
Environment: vCenter 8.0.3, ESXi 8.0, Windows Host

================================================================================
SYMPTOM
================================================================================
- Stage 2 of vCenter installation hangs at 0% for more than 30 minutes
- No progress indication or error messages displayed
- Installation appears frozen during appliance configuration

================================================================================
ROOT CAUSE
================================================================================
DNS resolution failure. vCenter cannot resolve its own FQDN (vsphere.local).

The vCenter appliance performs DNS lookups for its configured FQDN during Stage 2
initialization. If the FQDN cannot be resolved, the installation process enters
a wait state and appears to hang indefinitely.

================================================================================
TECHNICAL ANALYSIS
================================================================================
During Stage 2, vCenter:
1. Validates network configuration
2. Performs DNS resolution of configured FQDN
3. Initializes SSO (Single Sign-On) services
4. Configures internal services with FQDN references

Without proper DNS resolution, Step 2 fails silently, causing the hang.

================================================================================
SOLUTION OPTIONS
================================================================================

OPTION 1: Skip FQDN (Quick Fix - Not Recommended)
--------------------------------------------------
1. Cancel the installation
2. Restart Stage 1
3. In Step 5 (Network settings), leave System name BLANK or use IP address
4. Access vCenter via IP: https://192.168.0.101

Limitations:
- Some features require FQDN (Certificate Manager, external integrations)
- SSL certificates will use IP address
- Not suitable for production environments

OPTION 2: Configure Proper DNS Resolution (RECOMMENDED)
--------------------------------------------------------
Configure hosts file on Windows host machine:

File: C:\Windows\System32\drivers\etc\hosts

Required Entries:
192.168.0.100  esxi.localdomain   esxi
192.168.0.101  vsphere.local      vsphere

Note: Add more entries as you build (nested ESXi-1, ESXi-2, NAS, etc.)

Verification Commands (PowerShell):
# Test DNS resolution
nslookup vsphere.local

# Test connectivity
ping vsphere.local

# Test HTTPS port
Test-NetConnection -ComputerName vsphere.local -Port 443

Additional Checks if Installation Still Hangs:
- Ensure ESXi host can resolve vsphere.local (add to ESXi hosts file if needed)
- Verify no firewall blocking DNS queries
- Confirm vCenter VM has correct DNS server configuration

================================================================================
VERIFICATION
================================================================================
After applying fix:
1. Installation should progress past 0% within 5 minutes
2. Stage 2 should complete in 15-30 minutes
3. Access vCenter web client at https://vsphere.local

================================================================================
PREVENTION
================================================================================
1. Always configure DNS/hosts file BEFORE starting vCenter installation
2. Test DNS resolution from both Windows host and ESXi
3. Document all FQDN-to-IP mappings
4. Verify network connectivity before beginning installation

================================================================================
REFERENCES
================================================================================
Source: /DC-K8s/.archive/00-HOST-FOUNDATION/01-vcenter/05-troubleshooting.md
Related Cases: 02-vCenter-Authentication-Error (SSO alias whitelist)

================================================================================
LESSONS LEARNED
================================================================================
- DNS is critical for vCenter installation - never skip this step
- Silent failures in Stage 2 are almost always DNS-related
- Using IP addresses instead of FQDNs creates technical debt
- Proper planning prevents 30+ minute installation delays
