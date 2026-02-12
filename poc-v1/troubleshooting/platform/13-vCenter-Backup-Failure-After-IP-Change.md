================================================================================
CASE: vCenter Backup Failure After IP Change
================================================================================
Category: Platform - vCenter Backup
Severity: Medium
Date: Post-IP Migration
Environment: vCenter 8.0.3
Error: Backup task fails after IP and domain change

================================================================================
SYMPTOM
================================================================================
- vCenter automatic backup task fails immediately after starting
- Backup transfers approximately 20 MB then fails with no specific error code
- Issue occurs after changing vCenter IP from 192.168.0.101 to 10.0.20.89
- Issue occurs after changing domain from localhost to vcenter.home.lab
- Old backup folder (192.x) exists but new folder (vcenter.home.lab) shows chain issues

================================================================================
ROOT CAUSE
================================================================================
When vCenter's IP address or hostname changes, the backup service attempts to
continue using the existing backup chain. The backup metadata references the
old IP/hostname, causing a chain corruption issue when trying to write to a
new folder named after the new FQDN.

The backup service becomes stuck between:
1. Old backup location: /nfs/vcsa_vcenter/192.x/
2. New backup location: /nfs/vcsa_vcenter/vcenter.home.lab/

Additionally, corrupted backup schedule and history files persist from the
old configuration, preventing successful backup completion.

================================================================================
TECHNICAL ANALYSIS
================================================================================
Backup Chain Issue:
- vCenter backup uses incremental backup chains
- Chain metadata includes hostname/IP references
- Changing IP/hostname breaks chain continuity
- Service attempts to continue old chain in new location

Configuration Files:
- /storage/applmgmt/backup_restore/backup_schedule.json
- /storage/applmgmt/backup_restore/backup-history.json
- These files contain old configuration and corrupted state

Log Location:
- /var/log/vmware/applmgmt/backup.log

Common errors found in logs:
- WCP (Workload Control Plane) access issues
- Directory access failures
- Chain validation errors

================================================================================
SOLUTION: Reset Backup Configuration
================================================================================

Step 1: Check Backup Logs
--------------------------
ssh root@vcenter.home.lab
cat /var/log/vmware/applmgmt/backup.log | tail -200

Review errors to confirm chain/directory issues.

Step 2: Remove Old Backup Folders (Optional)
---------------------------------------------
# Only if old backups are no longer needed and snapshots exist
# Navigate to NFS mount and remove old backup folder
rm -rf /mnt/nfs/vcsa_vcenter/192.x

Step 3: Stop Appliance Management Service
------------------------------------------
service-control --stop applmgmt

This service controls the VAMI (port 5480) interface.

Step 4: Navigate to Backup Configuration Directory
---------------------------------------------------
cd /storage/applmgmt/backup_restore/

Step 5: Backup and Remove Configuration Files
----------------------------------------------
# Rename (or delete) corrupted configuration files
mv backup_schedule.json backup_schedule.json.old
mv backup-history.json backup-history.json.old

This clears the old corrupted schedule and history from the system.

Step 6: Start Appliance Management Service
-------------------------------------------
service-control --start applmgmt

Wait for service to fully initialize (2-3 minutes).

Step 7: Reconfigure Backup
---------------------------
1. Access VAMI: https://vcenter.home.lab:5480
2. Navigate to Backup section
3. Create new backup schedule with fresh configuration
4. Point to NFS location (will create new vcenter.home.lab folder)
5. Start manual backup to test

================================================================================
VERIFICATION
================================================================================
After applying fix:
1. Manual backup should complete successfully
2. New folder created: /nfs/vcsa_vcenter/vcenter.home.lab/
3. Check backup.log shows no errors:
   tail -f /var/log/vmware/applmgmt/backup.log

4. Scheduled backups run without failures
5. Backup status in VAMI shows green/successful

================================================================================
PREVENTION
================================================================================
1. Always delete old backup chains after IP/hostname changes
2. Create VM snapshots before major network configuration changes
3. Reset backup configuration after IP changes to start fresh chain
4. Document backup locations and naming conventions
5. Test backup functionality after any network changes
6. Consider using IP-based NFS paths instead of hostname-based paths

================================================================================
ALTERNATIVE APPROACHES
================================================================================
Option 1: Keep Old Backups (Not Recommended)
- Manually copy old backup folder to new hostname folder
- Risk of chain corruption remains
- More complex troubleshooting

Option 2: Use Consistent Backup Location
- Configure NFS path that doesn't include hostname
- Use /backup/vcenter/ instead of /backup/{hostname}/
- Prevents this issue during hostname changes

Option 3: External Backup Solution
- Use Veeam or other backup software
- Manages backup chains independently
- More robust for infrastructure changes

================================================================================
RELATED ISSUES
================================================================================
After IP change, also encountered:
- Veeam connectivity issues (required re-adding vCenter to Veeam)
- Certificate issues (required regenerating certificates for new IP/FQDN)
- See: 14-vSphere-Lifecycle-Manager-Plugin-Download-Error.md

================================================================================
REFERENCES
================================================================================
Source: draft for 29 (lines 1-36)
Log Location: /var/log/vmware/applmgmt/backup.log
Config Location: /storage/applmgmt/backup_restore/
Related Cases: Certificate regeneration after IP change

================================================================================
LESSONS LEARNED
================================================================================
- vCenter backup is sensitive to IP/hostname changes
- Always reset backup configuration after network changes
- Old backup metadata files must be cleared for fresh start
- Having VM snapshots before changes is critical safety net
- Test backups immediately after any infrastructure changes



########### Issue repeated after 1 day ###############


2026-01-03T10:56:34.841 [20260103-085630-24322831] [VCDB-WAL-Backup:PID-45139] [VCDB::_backup_wal_files:VCDB.py:821] INFO: Current WAL file is: 0000000100000001000000AC
2026-01-03T10:56:34.842 [20260103-085630-24322831] [VCDB-WAL-Backup:PID-45139] [VCDB::_backup_wal_files:VCDB.py:825] INFO: No new WAL files since last backup
2026-01-03T10:56:34.922 [20260103-085630-24322831] [LotusBackup:PID-45121] [Lotus::BackupLotus:Lotus.py:110] INFO: Lotus backup finished successfully.
2026-01-03T10:56:34.925 [20260103-085630-24322831] [LotusBackup:PID-45121] [Lotus::BackupLotusCleanup:Lotus.py:140] INFO: Successfully completed Lotus cleanup.
2026-01-03T10:56:34.926 [20260103-085630-24322831] [LotusBackup:PID-45121] [Lotus::BackupLotusCleanup:Lotus.py:140] INFO: Successfully completed Lotus cleanup.
2026-01-03T10:56:35.517 [20260103-085630-24322831] [ComponentScriptsBackup:PID-45119] [Log::run:Log.py:64] ERROR: 503 Server Error: Service Unavailable for url: http://localhost:1080/wcp
2026-01-03T10:56:35.654 [20260103-085630-24322831] [ComponentScriptsBackup:PID-45119] [ComponentScripts::ComponentScriptsBackup:ComponentScripts.py:106] ERROR: Component backup command "/etc/vmware/backup/component-scripts/wcp/wcp_backup_restore.py --startBackup" failed 1.
2026-01-03T10:56:35.654 [20260103-085630-24322831] [ComponentScriptsBackup:PID-45119] [Log::run:Log.py:64] ERROR: Failed to get etcd snapshot for all supervisor clusters: Failed to generate SAML token and                                         create sessionFailed to complete backup: Failed to generate SAML token and                                         create session
2026-01-03T10:56:35.655 [20260103-085630-24322831] [ComponentScriptsBackup:PID-45119] [ComponentScripts::ComponentScriptsBackup:ComponentScripts.py:135] ERROR: Error during component wcp backup
Underlying process status. rc: 1
stdout: 
stderr: 
Traceback (most recent call last):
  File "/usr/lib/applmgmt/backup_restore/py/vmware/appliance/backup_restore/components/ComponentScripts.py", line 110, in ComponentScriptsBackup
    raise BackupRestoreError(('Error during component %s backup' %
util.Common.BackupRestoreError: Error during component wcp backup
Underlying process status. rc: 1
stdout: 
stderr: 
2026-01-03T10:56:35.732 [20260103-085630-24322831] [MainProcess:PID-44980] [Proc::VerifyProcStatusAndGetArchive:Proc.py:159] ERROR: Error at process ComponentScriptsBackup; rc:1.
2026-01-03T10:56:35.732 [20260103-085630-24322831] [MainProcess:PID-44980] [Proc::VerifyProcStatusAndGetArchive:Proc.py:163] ERROR: stderr:Error during component wcp backup

2026-01-03T10:56:35.733 [20260103-085630-24322831] [MainProcess:PID-44980] [Proc::VerifyProcStatusAndGetArchive:Proc.py:172] INFO: Following error message isn't localized:
  stderr:Error during component wcp backup


If you DO use vSphere with Tanzu:
1. Check WCP service status:
bash# SSH to vCenter
vmon-cli --status wcp


root@vcenter [ ~ ]# vmon-cli --status wcp
Name: wcp
Starttype: MANUAL
RunState: STOPPED
RunAsUser: wcp
CurrentRunStateDuration(ms): 2824623
HealthState: UNHEALTHY
FailStop: FALSE
MainProcessId: N/A

because we set Workload Control Plane to duisable from web before and old backup involved it 
After enable the services, issue solved 

If it didnt solved you check continue check the servce log and ports
# Check if the service is listening
netstat -tuln | grep 1080

# Check WCP logs
tail -f /var/log/vmware/wcp/wcpsvc.log



If you DON'T use vSphere with Tanzu: for k8s you can disable the  service and exclude it from the backup by flaging its script and  folder, but better to not do that 
When i disbaled before it was for resources as i was going to reduce the mem from 15 to 7 gb 
but the service use few mem as checked now 

root@vcenter [ ~ ]# ps -eo pid,user,vsz,rss,%mem,%cpu,cmd | grep -i wcp | grep -v grep
  54194 wcp      6083488 66708  0.9 0.4 /usr/lib/vmware-wcp/wcpsvc --port 8920 --logfile /var/log/vmware/wcp/wcpsvc.log --configfile /etc/vmware/wcp/wcpsvc.yaml --audit-logfile /var/log/vmware/wcp/wcp-audit.log --incident-logfile /var/lo  54236 vpostgr+ 457320 46056  0.6  0.0 postgres: wcpuser VCDB [local] idle
  57938 vpostgr+ 448652 23944  0.3  0.0 postgres: wcpuser VCDB [local] idle

arroun 60 MB 
+ 40 and 40 MB for postgres related ,
so its not that much to be disabled . 
  
