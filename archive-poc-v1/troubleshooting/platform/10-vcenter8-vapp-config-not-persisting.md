================================================================================
CASE: vCenter 8 vApp Configuration Not Persisting After Restart
================================================================================
Category: Platform - vCenter 8 vApp Management / Database
Severity: High
Date: vApp Configuration Phase
Environment: VMware vCenter Server 8.0.3.0
Error: GUI configuration changes revert after vCenter restart

================================================================================
SYMPTOM
================================================================================
- vApp startup order and shutdown behavior settings configured through vCenter
  GUI fail to persist after vCenter restart
- Settings appear to save initially but randomly disappear or revert to defaults
- Startup order persists correctly Yes
- Shutdown behavior (Guest Shutdown, Suspend) reverts to "Power Off" No
- Startup delay settings revert to default (120s) No
- Changes appear saved in GUI but don't persist after vCenter service restart
- Behavior is random and inconsistent

Example Configuration Loss:
---------------------------
Before vCenter restart:
- pfSense: Shutdown = Guest Shutdown, Delay = 60s
- IPA Server: Shutdown = Guest Shutdown, Delay = 100s
- Workers: Shutdown = Guest Shutdown, Delay = 120s

After vCenter restart:
- pfSense: Shutdown = Power Off, Delay = 120s (REVERTED!)
- IPA Server: Shutdown = Power Off, Delay = 120s (REVERTED!)
- Workers: Shutdown = Power Off, Delay = 120s (REVERTED!)

================================================================================
ROOT CAUSE
================================================================================
vCenter 8.0.3.0 has a bug where GUI writes to vApp configuration fail to
commit to the PostgreSQL database properly.

Technical Root Cause:
---------------------
1. GUI writes appear to complete successfully (no error shown to user)
2. Database UPDATE transactions are not being committed properly
3. vpxd service has transaction commit issues
4. Database connections destroyed before COMMIT is executed
5. Manual database edits DO persist (proving database itself is functional)

Evidence from Logs:
-------------------
/var/log/vmware/vpxd/vpxd.log shows:

```
2025-12-06T10:52:53.916+02:00 info vpxd[06388] [VpxLRO] -- BEGIN task-37017 -- resgroup-v19002 -- vim.VirtualApp.updateVAppConfig
2025-12-06T10:52:53.917+02:00 warning vpxd[06388] [Vdb::Connection::~VdbWriteConnection] SQL Statement 1: UPDATE VPX_RESOURCE_POOL SET CONFIG_SPEC=?,FOLDER_ID=?,VAPP_CONFIG=?,MANAGED_BY_EXT_KEY=?,MANAGED_BY_TYPE=? WHERE ID=?
```

Key Finding: The `warning` message about `~VdbWriteConnection` (destructor)
indicates the database connection is being closed/destroyed BEFORE the
transaction commits.

Database Transaction Flow (BROKEN):
------------------------------------
1. User clicks "Save" in vCenter GUI
2. vpxd initiates database transaction: BEGIN
3. vpxd executes UPDATE statement on vpx_resource_pool table
4. Connection object destroyed (~VdbWriteConnection destructor called)
5. Transaction NEVER commits (no COMMIT statement executed)
6. Changes lost when connection closes
7. GUI shows success (because no error was raised)
8. User thinks settings saved, but they didn't

Verification:
-------------
- GUI writes: Settings appear in GUI, disappear after restart
- Database writes: Settings persist across restarts
- Conclusion: GUI write path is broken, database is functional

================================================================================
AFFECTED vCENTER VERSIONS
================================================================================
Confirmed Affected:
- vCenter Server 8.0.3.0 (Build XXXX)

Potentially Affected:
- vCenter 8.0.x series (needs verification)

Not Affected:
- vCenter 7.x (not confirmed, but different codebase)

Check Your Version:
-------------------
vCenter Web UI → Menu → About VMware vCenter Server
Or via SSH:
```bash
vpxd -v
```

================================================================================
IMPACT ANALYSIS
================================================================================
Business Impact:
----------------
- vApp startup/shutdown automation unreliable
- VMs may power off forcefully instead of guest shutdown
- Risk of data corruption (databases not flushed)
- Operational overhead (manual startup sequencing required)
- Dependency failures (apps start before DNS/network ready)

Technical Impact:
-----------------
- Guest Shutdown ensures graceful termination (database flush, connection cleanup)
- Power Off is equivalent to pulling power (data loss risk)
- Startup delays ensure dependencies are ready
- Without proper config: crash loops, failed starts, service unavailability

Example Failure Scenario:
-------------------------
1. Kubernetes worker starts before master API is ready
2. kubelet fails to register, pod startup fails
3. Requires manual intervention to bring cluster online
4. If Power Off used instead of Guest Shutdown:
   - etcd database may not flush to disk
   - LDAP database may have uncommitted transactions
   - VM filesystems may require fsck on next boot

================================================================================
DIAGNOSTIC PROCEDURES
================================================================================

Diagnosis 1: Verify GUI vs Database Mismatch
---------------------------------------------
Step 1: Check GUI Settings
Navigate to vCenter UI:
1. Inventory → vApps → Select your vApp
2. Click "Start Order" tab
3. Document current settings shown in GUI

Step 2: Check Database Values
```bash
ssh root@vcenter.home.lab
su - postgres
/opt/vmware/vpostgres/current/bin/psql -d VCDB
```

```sql
-- Find your vApp
SELECT
    e.name as vapp_name,
    e.id,
    rp.vapp_config
FROM vpx_resource_pool rp
JOIN vpx_entity e ON e.id = rp.id
WHERE rp.vapp_config IS NOT NULL;
```

Step 3: Compare Values
If GUI shows "Guest Shutdown" but database shows "powerOff" → BUG CONFIRMED

Diagnosis 2: Test GUI Write Functionality
------------------------------------------
1. Make a small change in GUI (e.g., change one VM to "Suspend")
2. Note the exact time of save
3. Immediately check database:

```sql
SELECT vapp_config FROM vpx_resource_pool WHERE id = <VAPP_ID>;
```

4. Search for your change (e.g., `<stopAction>suspend</stopAction>`)
5. If change NOT in database → GUI writes failing

Diagnosis 3: Check vpxd Logs for Transaction Warnings
------------------------------------------------------
```bash
# Search logs around the time you made GUI change
grep -i "UpdateVAppConfig\|~VdbWriteConnection" /var/log/vmware/vpxd/vpxd.log | grep "<TIME>"
```

Look for:
- BEGIN task message (transaction starts)
- ~VdbWriteConnection warning (connection destroyed before commit)
- NO matching COMMIT message

Diagnosis 4: Test Database Write Directly
------------------------------------------
Confirm database itself works:

```sql
-- Test update
UPDATE vpx_resource_pool
SET vapp_config = REPLACE(
    vapp_config,
    '<stopAction>powerOff</stopAction>',
    '<stopAction>guestShutdown</stopAction>'
)
WHERE id = <VAPP_ID>
LIMIT 1;

-- Check if change persisted
SELECT vapp_config FROM vpx_resource_pool WHERE id = <VAPP_ID>;
```

If change appears in query → Database works, GUI is the problem

================================================================================
WORKAROUND SOLUTION: DIRECT DATABASE CONFIGURATION
================================================================================
Since GUI writes fail but database edits persist, configure vApp directly
via PostgreSQL database.

CRITICAL PREREQUISITES
----------------------
Before making ANY database changes:

1. Take vCenter VM snapshot (hypervisor level)
   - Name: Before_vApp_DB_Edit_YYYY-MM-DD
   - Include Memory: Yes

2. Backup vCenter database:
```bash
ssh root@vcenter.home.lab
su - postgres
/opt/vmware/vpostgres/current/bin/pg_dump VCDB > /tmp/vcdb_backup_$(date +%F_%H%M%S).sql
/opt/vmware/vpostgres/current/bin/pg_dump VCDB -t vpx_resource_pool > /tmp/vapp_table_backup_$(date +%F_%H%M%S).sql
exit
cp /tmp/*backup* /root/
```

3. Power off vApp (recommended):
   - Reduces risk of runtime conflicts
   - Prevents inconsistencies during edit

4. Create backup table:
```sql
CREATE TABLE vpx_resource_pool_backup_vapp AS
SELECT * FROM vpx_resource_pool WHERE id = <VAPP_ID>;
```

SOLUTION IMPLEMENTATION
-----------------------

Step 1: Connect to Database
----------------------------
```bash
ssh root@vcenter.home.lab
su - postgres
/opt/vmware/vpostgres/current/bin/psql -d VCDB
```

Step 2: Find Your vApp ID
--------------------------
```sql
SELECT
    e.name as vapp_name,
    e.id as vapp_id
FROM vpx_resource_pool rp
JOIN vpx_entity e ON e.id = rp.id
WHERE rp.vapp_config IS NOT NULL;
```

Note the vApp ID (e.g., 19002)

Step 3: View Current Configuration
-----------------------------------
```sql
SELECT * FROM (
    SELECT
        unnest(xpath('//entityConfig/tag/text()', vapp_config::xml))::text AS vm_name,
        unnest(xpath('//entityConfig/startOrder/text()', vapp_config::xml))::text AS start_order,
        unnest(xpath('//entityConfig/startDelay/text()', vapp_config::xml))::text AS start_delay_sec,
        unnest(xpath('//entityConfig/stopAction/text()', vapp_config::xml))::text AS stop_action,
        unnest(xpath('//entityConfig/stopDelay/text()', vapp_config::xml))::text AS stop_delay_sec
    FROM vpx_resource_pool
    WHERE id = <VAPP_ID>
) AS vapp_data
ORDER BY start_order::int;
```

Step 4: Update All VMs to Guest Shutdown
-----------------------------------------
```sql
-- Change all powerOff to guestShutdown
UPDATE vpx_resource_pool
SET vapp_config = REPLACE(
    vapp_config,
    '<stopAction>powerOff</stopAction>',
    '<stopAction>guestShutdown</stopAction>'
)
WHERE id = <VAPP_ID>;

-- Also replace any suspend if you want all guestShutdown
UPDATE vpx_resource_pool
SET vapp_config = REPLACE(
    vapp_config,
    '<stopAction>suspend</stopAction>',
    '<stopAction>guestShutdown</stopAction>'
)
WHERE id = <VAPP_ID>;

-- Verify changes
SELECT * FROM (
    SELECT
        unnest(xpath('//entityConfig/tag/text()', vapp_config::xml))::text AS vm_name,
        unnest(xpath('//entityConfig/stopAction/text()', vapp_config::xml))::text AS stop_action
    FROM vpx_resource_pool
    WHERE id = <VAPP_ID>
) AS vapp_data;
```

Expected output: All VMs show stopAction = guestShutdown

Step 5: Update Startup Delays (If Needed)
------------------------------------------
Example: Change pfSense startup delay from 120s to 60s

```sql
UPDATE vpx_resource_pool
SET vapp_config = REPLACE(
    vapp_config,
    'vm-XXXX</key><tag>pfSense</tag><startOrder>1</startOrder><startDelay>120</startDelay>',
    'vm-XXXX</key><tag>pfSense</tag><startOrder>1</startOrder><startDelay>60</startDelay>'
)
WHERE id = <VAPP_ID>;
```

Note: Replace vm-XXXX with actual VM managed object ID from step 3

Step 6: Verify Final Configuration
-----------------------------------
```sql
SELECT * FROM (
    SELECT
        unnest(xpath('//entityConfig/tag/text()', vapp_config::xml))::text AS vm_name,
        unnest(xpath('//entityConfig/startOrder/text()', vapp_config::xml))::text AS start_order,
        unnest(xpath('//entityConfig/startDelay/text()', vapp_config::xml))::text AS start_delay_sec,
        unnest(xpath('//entityConfig/stopAction/text()', vapp_config::xml))::text AS stop_action,
        unnest(xpath('//entityConfig/stopDelay/text()', vapp_config::xml))::text AS stop_delay_sec
    FROM vpx_resource_pool
    WHERE id = <VAPP_ID>
) AS vapp_data
ORDER BY start_order::int;
```

All settings should match your desired configuration.

Step 7: Exit Database
----------------------
```sql
\q
```
```bash
exit  # Exit postgres user
```

Step 8: Restart vCenter Services
---------------------------------
```bash
# Restart vpxd to reload configuration
service-control --stop vmware-vpxd
service-control --start vmware-vpxd

# Wait 90 seconds for service startup
sleep 90
```

Step 9: Verify GUI Reflects Changes
------------------------------------
1. Open vCenter GUI in browser
2. Press F5 to refresh
3. Navigate to vApp → Start Order tab
4. Verify configuration matches database

Step 10: Test Persistence (CRITICAL)
-------------------------------------
```bash
# Full restart of all vCenter services
service-control --stop --all
service-control --start --all

# Wait 2-3 minutes for full startup
```

After restart:
1. Check GUI again (should still show correct config)
2. Check database again (should still show correct config)
3. Success criteria: Both GUI and database match desired configuration

================================================================================
VERIFICATION CHECKLIST
================================================================================

Pre-Change Verification:
□ vCenter VM snapshot taken
□ Database full backup created
□ vApp table backup created
□ vApp powered off
□ Backup table created in database

Configuration Verification:
□ vApp ID identified
□ Current config documented
□ Changes applied to database
□ Database shows correct values
□ vpxd service restarted
□ GUI reflects database changes

Persistence Verification:
□ Full vCenter restart completed
□ Database config persists after restart
□ GUI config persists after restart
□ vApp startup test successful
□ VMs start in correct order
□ VMs use correct shutdown actions
□ Startup delays work as configured

================================================================================
TESTING PROCEDURES
================================================================================

Test 1: vApp Startup Order
---------------------------
1. Power on vApp (right-click → Power → Power On)
2. Watch VM console windows
3. Verify startup sequence:
   - pfSense boots first
   - Wait 60s (or configured delay)
   - IPA Server boots second
   - Wait 100s (or configured delay)
   - Remaining VMs boot in order

Expected: VMs boot in correct order with correct delays

Test 2: vApp Shutdown Behavior
-------------------------------
1. Power off vApp (right-click → Power → Power Off)
2. Watch VM consoles
3. Verify shutdown actions:
   - VMs shutdown in reverse order
   - Guest Shutdown initiated (not hard power off)
   - Each VM waits for shutdown delay
   - Last VM (pfSense) shuts down cleanly

Expected: All VMs use guestShutdown, not powerOff

Test 3: Persistence After vCenter Restart
------------------------------------------
1. Restart all vCenter services
2. Wait for full startup
3. Check database configuration
4. Check GUI configuration
5. Power on vApp and verify order

Expected: Configuration unchanged after restart

================================================================================
MONITORING & MAINTENANCE
================================================================================

Regular Checks:
---------------
Weekly:
- Verify GUI shows correct vApp settings
- Spot-check database for configuration drift

After vCenter Updates/Patches:
- Re-verify vApp configuration immediately
- Check if patch fixes GUI write issue
- Reapply database edits if reverted

After vCenter Restarts:
- Quick check that configuration persisted
- Test vApp startup to confirm

Automated Monitoring Script:
-----------------------------
```bash
#!/bin/bash
# /root/vapp_config_check.sh

VAPP_ID=19002
EXPECTED_GUEST_SHUTDOWN_COUNT=7  # Adjust to your VM count

CURRENT_COUNT=$(su - postgres -c "/opt/vmware/vpostgres/current/bin/psql -d VCDB -t -c \"SELECT vapp_config FROM vpx_resource_pool WHERE id = $VAPP_ID;\"" | grep -o "guestShutdown" | wc -l)

if [ "$CURRENT_COUNT" -ne "$EXPECTED_GUEST_SHUTDOWN_COUNT" ]; then
    echo "WARNING: vApp config changed! Expected $EXPECTED_GUEST_SHUTDOWN_COUNT, found $CURRENT_COUNT"
    echo "Configuration may have reverted. Re-run database update."
    exit 1
else
    echo "OK: vApp config correct ($CURRENT_COUNT/$EXPECTED_GUEST_SHUTDOWN_COUNT guestShutdown)"
    exit 0
fi
```

Schedule via cron:
```bash
# Check daily at 6 AM
0 6 * * * /root/vapp_config_check.sh
```

================================================================================
ROLLBACK PROCEDURES
================================================================================

If Database Edit Causes Issues:

Option 1: Restore from Backup Table (Fastest)
----------------------------------------------
```sql
DELETE FROM vpx_resource_pool WHERE id = <VAPP_ID>;
INSERT INTO vpx_resource_pool SELECT * FROM vpx_resource_pool_backup_vapp;
```

Option 2: Restore from SQL Dump
--------------------------------
```bash
service-control --stop --all
su - postgres
/opt/vmware/vpostgres/current/bin/psql -d VCDB < /tmp/vcdb_backup_YYYY-MM-DD_HHMMSS.sql
exit
service-control --start --all
```

Option 3: Revert to VM Snapshot (Safest)
-----------------------------------------
1. Power off vCenter VM
2. Revert to snapshot: Before_vApp_DB_Edit_YYYY-MM-DD
3. Power on vCenter VM
4. Wait for services (3-5 minutes)

================================================================================
PREVENTION & BEST PRACTICES
================================================================================

DO:
- Always backup before database edits
- Test changes in non-production first (if possible)
- Make incremental changes and verify each
- Use precise REPLACE strings to avoid unintended changes
- Stop vApp before editing database
- Document VM IDs and configuration
- Monitor for configuration drift
- Test persistence after every change

DON'T:
- Edit database while vApp is running
- Use generic REPLACE strings (could modify wrong VMs)
- Skip verification steps
- Skip backups
- Edit production without testing
- Trust GUI alone - always verify in database
- Assume settings will persist without testing

================================================================================
VMWARE KB AND SUPPORT
================================================================================

Reporting to VMware:
--------------------
If you encounter this issue, consider opening a VMware support case:

1. Collect Evidence:
   - vpxd.log showing ~VdbWriteConnection warnings
   - Screenshots of GUI showing settings
   - Database query showing different values
   - Steps to reproduce

2. VMware KB Search:
   - Search for "vApp configuration not persisting"
   - Search for "vCenter 8 vApp database commit"
   - Check for known issues in vCenter 8.0.x release notes

3. Support Case:
   - Priority: P2 (Significant business impact)
   - Product: vCenter Server 8.0.3
   - Issue: vApp configuration persistence bug

================================================================================
REFERENCES
================================================================================
Source: /DC-K8s/.archive/.../07-vApp-Orchestration/05-vcenter8-troubleshooting.md
Related Cases:
  - Other vCenter platform cases
VMware Docs: vCenter Server Administration Guide - vApp Management
PostgreSQL Docs: Transaction Management

================================================================================
LESSONS LEARNED
================================================================================
- GUI success messages don't guarantee database commits
- Database transaction logging reveals hidden failures
- Manual database edits work when automated systems fail
- Always verify configuration in database, not just GUI
- Backup strategy is critical before database modifications
- Testing persistence after changes is non-negotiable
- vCenter 8.x introduces bugs not present in 7.x
- Direct database access is powerful but requires caution
- Monitoring detects configuration drift before it causes outages
- Trust but verify - even vendor GUIs can have bugs
================================================================================
CASE UPDATE: SECOND OCCURRENCE & SOLUTION EVOLUTION
================================================================================
Date: 2025-12-25
Environment: Production cluster with single production server

SITUATION
================================================================================
Encountered the same vApp configuration persistence issue on a different
production environment. However, environmental constraints led to a different
solution approach.

KEY ENVIRONMENTAL FACTORS
================================================================================
1. Single production server deployment (not multi-server vApp cluster)
2. Simpler VM orchestration requirements
3. Need for long-term maintenance sustainability
4. Risk assessment favors avoiding database manipulation

TECHNICAL ROOT CAUSE ANALYSIS
================================================================================
Re-verified the underlying bug through vpxd logs:

Log Evidence:
-------------
2025-12-25T14:38:00.617+02:00 warning vpxd[06589] [Vdb::~VdbWriteConnection]
  Connection is released with uncommitted SQL statements
2025-12-25T14:38:00.617+02:00 warning vpxd[06589] [Vdb::Connection::~VdbWriteConnection]
  Transaction took 1 ms with 1 statements
2025-12-25T14:38:00.617+02:00 warning vpxd[06589] [Vdb::Connection::~VdbWriteConnection]
  SQL Statement 1: UPDATE VPX_RESOURCE_POOL SET CONFIG_SPEC=?,FOLDER_ID=?,
  VAPP_CONFIG=?,MANAGED_BY_EXT_KEY=?,MANAGED_BY_TYPE=? WHERE ID=?

Root Cause Confirmed:
---------------------
- UPDATE statement executes against vpx_resource_pool table
- Database connection closes BEFORE COMMIT
- PostgreSQL automatically ROLLS BACK uncommitted transaction
- Changes never persisted to disk
- vCenter reads old config from database after restart
- This is a confirmed bug in vCenter 8.0.3 build-24322831

Transaction Flow (What Goes Wrong):
------------------------------------
1. User saves vApp config via GUI
2. GUI sends UPDATE to vpxd service
3. vpxd executes: UPDATE VPX_RESOURCE_POOL SET VAPP_CONFIG=? WHERE ID=?
4.  Database connection destroyed before COMMIT issued
5. PostgreSQL automatically rolls back uncommitted work
6. GUI shows "saved" but database unchanged
7. vCenter restart loads old config from database

Database Verification:
----------------------
sql
-- Check current vApp configuration in database:
SELECT vapp_config FROM vpx_resource_pool WHERE id = 41001;

-- Expected: startDelay=60, stopAction=shutdown (your changes)
-- Actual:   startDelay=120, stopAction=powerOff (defaults - UNCHANGED!)


SOLUTION COMPARISON & DECISION
================================================================================

Option 1: Direct SQL Injection (Previous Workaround)
-----------------------------------------------------
- Pros:
  - Immediate fix
  - Works around the bug
  - Configuration persists correctly

- Cons:
  - Requires manual database intervention for every change
  - Database schema may change with vCenter patches/upgrades
  - Risk of data corruption if XML format incorrect
  - Maintenance burden for ongoing configuration changes
  - Requires PostgreSQL expertise
  - NOT suitable for production with frequent changes

Risk Assessment: HIGH for long-term production use

Option 2: PowerCLI Scripted Workaround
---------------------------------------
- Pros:
  - Automated configuration updates
  - Repeatable process

- Cons:
  - Still fighting against the underlying bug
  - Requires maintaining custom scripts
  - May break with vCenter updates
  - Additional complexity layer

Risk Assessment: MEDIUM-HIGH

Option 3: ESXi Native VM Autostart (RECOMMENDED) 
---------------------------------------------------
- Pros:
  - No vCenter database dependency
  - Configuration stored on ESXi host (survives vCenter issues)
  - Works even when vCenter is offline
  - Simpler architecture
  - No transaction commit bugs
  - Native VMware feature (fully supported)
  - Survives vCenter restarts/upgrades/migrations
  - No ongoing maintenance burden
  - Suitable for single-server production deployments

- Cons:
  - Requires migrating away from vApp construct
  - Must update automation scripts/documentation
  - Loss of vApp-specific features (if used)

Risk Assessment: LOW

DECISION RATIONALE
================================================================================
Selected Option 3: ESXi Native VM Autostart

Why This Decision:
------------------
1. Environmental Fit:
   - Single production server = ESXi autostart sufficient
   - No complex multi-VM orchestration needed
   - vApp features not utilized beyond startup/shutdown

2. Risk Reduction:
   - Eliminates database injection risks
   - Removes dependency on buggy vCenter transaction handling
   - Reduces maintenance complexity

3. Sustainability:
   - No ongoing manual database interventions required
   - Configuration changes through standard ESXi interfaces
   - Future-proof against vCenter updates/migrations

4. Operational Benefits:
   - VM autostart works even if vCenter unavailable
   - Configuration local to ESXi host (more resilient)
   - Simpler troubleshooting path

IMPLEMENTATION GUIDE FOR FUTURE OCCURRENCES
================================================================================

When to Use Each Solution:
--------------------------

USE ESXi VM AUTOSTART when:
  Yes Single ESXi host or simple cluster
  Yes Basic startup/shutdown sequencing needed
  Yes vApp features not actively used
  Yes Production environment with stability priority
  Yes Want to avoid vCenter database dependencies

USE SQL INJECTION WORKAROUND when:
  Yes Complex vApp orchestration genuinely needed
  Yes Multi-tier applications with interdependencies
  Yes Temporary fix while awaiting vendor patch
  Yes Non-production or lab environments
  Yes Team has strong PostgreSQL expertise

Migration Path (vApp to ESXi Autostart):
-----------------------------------------
1. Document current vApp configuration:
   - Startup order
   - Delay timings (e.g., 60s, 100s, 120s)
   - Shutdown actions (Guest Shutdown vs Power Off)

2. Configure ESXi VM Autostart:
   - Host > Configure > Virtual Machines > VM Startup/Shutdown
   - Set startup delays matching vApp config
   - Set shutdown actions (Guest Shutdown preferred)
   - Enable autostart for required VMs

3. Test autostart behavior:
   - Reboot ESXi host (maintenance mode)
   - Verify VM startup sequence
   - Verify shutdown behavior

4. Remove vApp container:
   - Right-click vApp > Remove from Inventory
   - VMs remain intact, only container removed

5. Update automation/documentation:
   - Update references from vApp to ESXi autostart
   - Update runbooks and procedures
   - Notify team of configuration change

VERIFICATION STEPS
================================================================================
After implementing ESXi Autostart:

1. Check ESXi autostart config:
   vim-cmd hostsvc/autostartmanager/get_config

2. Reboot ESXi host (during maintenance window):
   - Verify VMs start in correct order
   - Verify delays are respected
   - Check VM logs for clean startup

3. Test shutdown behavior:
   - Put host in maintenance mode with VM migration disabled
   - Verify Guest Shutdown executed (not Power Off)
   - Check VM shutdown order

LESSONS LEARNED - UPDATED
================================================================================
- One-size-fits-all solutions don't exist - evaluate environment first
- Direct database fixes should be temporary, not permanent solutions
- Native platform features (ESXi autostart) often more reliable than
  higher-level abstractions (vApp)
- When vendor bugs impact core functionality, architectural workarounds
  may be better than tactical fixes
- Production systems benefit from simpler, vendor-supported approaches
- Reducing dependencies (vCenter DB) improves resilience
- Context matters: same bug, different environment = different solution