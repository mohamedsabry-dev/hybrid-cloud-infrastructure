================================================================================
CASE: Certificate Manager "Failed to Replace Certificate" Error
================================================================================
Category: Platform - vCenter Certificate Management
Severity: High
Date: During Certificate Replacement
Environment: vCenter 8.0.3
Error: "Failed to Replace Certificate"

================================================================================
SYMPTOM
================================================================================
- Certificate Manager replacement operation fails
- Error displayed: "Failed to Replace Certificate"
- Operation times out or shows generic error message
- Certificate replacement workflow cannot complete

================================================================================
ROOT CAUSE ANALYSIS
================================================================================
Three primary causes for certificate replacement failures:

CAUSE 1: vCenter Services Not Responding
-----------------------------------------
Symptoms:
- Long timeout before error appears
- Multiple services showing degraded performance
- High CPU or memory utilization on vCenter
- Slow response from vCenter web client

Root Cause:
- Service deadlock or resource exhaustion
- Certificate service dependencies not running
- Internal service timeouts

CAUSE 2: Incorrect SSO Password
--------------------------------
Symptoms:
- Immediate authentication failure
- Error mentions SSO or authentication
- Operation rejected at early stage

Root Cause:
- Wrong password for administrator@vsphere.local
- SSO service cannot authenticate operation
- Certificate operations require SSO admin rights

CAUSE 3: Disk Space Full on vCenter
------------------------------------
Symptoms:
- Error about storage or disk space
- Logs show write failures
- Certificate backup cannot be created

Root Cause:
- /storage partition full (logs, db, backups)
- Certificate backup process requires free space
- Transaction logs accumulating

================================================================================
DIAGNOSTIC PROCEDURES
================================================================================

Diagnosis 1: Check Service Health
----------------------------------
SSH to vCenter:
ssh root@192.168.0.101
shell

Check all services:
service-control --status --all

Look for STOPPED or DEGRADED services, particularly:
- vmware-certificatemanagement
- vmware-vmcam
- vmware-vmon
- vsphere-ui

Diagnosis 2: Verify SSO Credentials
------------------------------------
Test authentication:
# From vCenter shell
/usr/lib/vmware-vmafd/bin/dir-cli trustedcert list \
  --login administrator@vsphere.local \
  --password 'YourPassword'

If credentials work, you'll see certificate list.
If wrong password, you'll get authentication error.

Diagnosis 3: Check Disk Space
------------------------------
SSH to vCenter:
ssh root@192.168.0.101
shell

Check disk usage:
df -h

Critical partitions to check:
/storage/log    - Should be < 80%
/storage/db     - Should be < 80%
/              - Should be < 80%

Detailed storage breakdown:
df -h /storage/log
df -h /storage/db
du -sh /storage/log/*
du -sh /storage/db/*

================================================================================
SOLUTIONS BY ROOT CAUSE
================================================================================

SOLUTION 1: Restart vCenter Services
-------------------------------------
If services are not responding or degraded:

Step 1: Reboot vCenter VM
--------------------------
From vSphere Client:
1. Right-click vCenter VM
2. Power > Restart Guest OS

OR via SSH:
reboot

Step 2: Wait for All Services to Start
---------------------------------------
This can take 5-10 minutes for full initialization.

Monitor service startup:
watch -n 5 'service-control --status --all'

Wait until all critical services show STARTED.

Step 3: Retry Certificate Replacement
--------------------------------------
1. Login to vCenter Web Client
2. Menu > Administration > Certificate Management
3. Retry certificate replacement operation

SOLUTION 2: Verify and Reset SSO Password
------------------------------------------
If SSO password is wrong or forgotten:

Option A: Reset from VAMI
-------------------------
1. Access VAMI: https://192.168.0.101:5480
2. Login with root credentials
3. Navigate to Administration
4. Reset administrator@vsphere.local password

Option B: Reset from Shell
---------------------------
SSH to vCenter:
shell

Reset SSO password:
/usr/lib/vmware-vmdir/bin/vdcadmintool
# Choose option 3: Reset account password
# Enter: administrator@vsphere.local

Step 3: Retry with Correct Password
------------------------------------
Use new password in Certificate Manager operation.

SOLUTION 3: Free Up Disk Space
-------------------------------
If disk space is full:

Step 1: Identify Large Files
-----------------------------
du -sh /storage/log/* | sort -rh | head -20
du -sh /storage/db/* | sort -rh | head -20

Step 2: Archive Old Logs
-------------------------
# Compress logs older than 30 days
find /storage/log -name "*.log" -mtime +30 -exec gzip {} \;

# Or remove very old logs
find /storage/log -name "*.log" -mtime +90 -delete

Step 3: Clean Database Transaction Logs
----------------------------------------
# Check PostgreSQL disk usage
du -sh /storage/db/vmware-vpostgres/

# Vacuum database (from vCenter shell)
/opt/vmware/vpostgres/current/bin/vacuumdb --all

Step 4: Clean Core Dumps
-------------------------
# Check for core dumps
ls -lh /storage/core/

# Remove old core dumps (if not needed for debugging)
rm -f /storage/core/*

Step 5: Verify Free Space
--------------------------
df -h

Ensure at least 20% free space on /storage partitions.

Step 6: Retry Certificate Replacement
--------------------------------------
After freeing space, retry the operation.

================================================================================
VERIFICATION
================================================================================
After applying fixes:

1. Service Health Check:
   service-control --status --all
   All critical services should show STARTED

2. Disk Space Check:
   df -h
   All partitions should have >20% free

3. SSO Authentication Test:
   Login to vCenter web client successfully

4. Certificate Replacement Test:
   Navigate to Certificate Manager
   Initiate certificate replacement
   Operation should complete without errors

================================================================================
PREVENTION
================================================================================
1. Monitor vCenter disk space (set alerts at 70%)
2. Implement log rotation policies
3. Schedule regular vCenter reboots (monthly)
4. Document SSO password in secure vault
5. Test certificate replacement in non-production first
6. Maintain backups before certificate operations
7. Schedule certificate renewals before expiration

================================================================================
RELATED DIAGNOSTIC COMMANDS
================================================================================

Service Management:
-------------------
# List all services
service-control --status --all

# Start specific service
service-control --start vmware-certificatemanagement

# Stop specific service
service-control --stop vmware-certificatemanagement

# Restart all services
service-control --restart --all

Certificate Verification:
-------------------------
# Check Machine SSL certificate
openssl s_client -connect localhost:443 </dev/null 2>/dev/null | openssl x509 -noout -dates

# List trusted root certificates
/usr/lib/vmware-vmafd/bin/vecs-cli entry list --store TRUSTED_ROOTS

# Check certificate expiration
for store in MACHINE_SSL_CERT TRUSTED_ROOTS; do
  echo "=== $store ==="
  /usr/lib/vmware-vmafd/bin/vecs-cli entry list --store $store
done

================================================================================
REFERENCES
================================================================================
Source: /DC-K8s/.archive/00-HOST-FOUNDATION/01-vcenter/05-troubleshooting.md
Related Cases: 04-vCenter-Certificate-Browser-Error
VMware KB: vCenter Certificate Management
Docs: vSphere Certificate Manager Administration Guide

================================================================================
LESSONS LEARNED
================================================================================
- Certificate operations require healthy service state
- Always verify prerequisites (disk space, services) before cert operations
- SSO password is critical - document in secure location
- Disk space monitoring prevents many operational failures
- Rebooting vCenter is often the fastest fix for service issues
- Test certificate procedures in lab before production
- Backup vCenter before certificate replacement operations
- Certificate operations timeout if vCenter is under heavy load
