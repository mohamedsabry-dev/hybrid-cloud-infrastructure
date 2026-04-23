================================================================================
CASE: FreeIPA Kerberos Clock Skew - Time Synchronization Issues
================================================================================
Category: Platform - FreeIPA / Kerberos / NTP
Severity: High
Incident: Yes
Date: Post-IPA Installation / Runtime
Environment: FreeIPA Server, Multiple VMs, VMware Tools
Error: "Clock skew too great" / Kerberos authentication fails

================================================================================
SYMPTOM
================================================================================
- Kerberos authentication fails intermittently
- "Clock skew too great" errors in logs
- SSH or IPA commands work sometimes, fail other times
- Services can't authenticate to each other
- Time differences visible between VMs

Example Error Messages:
```
ipa: ERROR: Kerberos error: Clock skew too great
kinit: Clock skew too great while getting initial credentials
SSH login fails: "GSS-API authentication failed"
```

Symptoms by Time Difference:
- <5 minutes: Intermittent failures
- 5-10 minutes: Frequent failures
- >10 minutes: Total authentication failure

================================================================================
ROOT CAUSE
================================================================================
VMs syncing time from different sources or conflicting time sync mechanisms
create time drift that exceeds Kerberos tolerance (default: 5 minutes).

Multiple Time Sources Problem:
-------------------------------
1. VMware Tools time sync (syncs to ESXi host)
2. chrony/NTP pointing to external servers
3. chrony pointing to IPA server
4. Multiple NTP pools configured
5. DHCP-provided NTP servers

Result: VMs jump between time sources, creating drift

Kerberos Time Sensitivity:
---------------------------
Kerberos uses timestamps to prevent replay attacks:
- Client ticket includes timestamp
- Server validates timestamp is within acceptable skew
- Default max skew: 5 minutes
- If client time differs > 5 minutes, ticket rejected

Example Failure Scenario:
-------------------------
1. IPA server time: 12:00:00 (correct)
2. Client VM time: 12:06:00 (6 minutes ahead)
3. Client requests Kerberos ticket
4. Ticket timestamp: 12:06:00
5. IPA server checks: |12:06:00 - 12:00:00| = 6 minutes
6. 6 minutes > 5 minute tolerance → REJECT
7. Authentication fails

VMware Tools Conflict:
----------------------
- VMware Tools time sync periodically syncs to ESXi host time
- ESXi host may sync to different NTP source than IPA
- Guest VM's chrony tries to sync to IPA
- VMware Tools overrides chrony's adjustment
- Result: Constant time drift battle between two mechanisms

================================================================================
DIAGNOSTIC PROCEDURES
================================================================================

Diagnosis 1: Check Time on All Systems
---------------------------------------
On each VM:
```bash
date
timedatectl
```

Compare outputs across VMs:
- IPA Server: Mon Dec 25 12:00:00 UTC 2025
- K8s Master: Mon Dec 25 12:03:00 UTC 2025  ← 3 min drift
- Worker 1:   Mon Dec 25 11:55:00 UTC 2025  ← 5 min drift (PROBLEM)

If drift > 2 minutes, investigate time sync configuration

Diagnosis 2: Check VMware Tools Time Sync Status
-------------------------------------------------
On each VM:
```bash
vmware-toolbox-cmd timesync status
```

Problematic output:
```
Enabled
```

This means VMware Tools is overriding OS time sync

Expected output:
```
Disabled
```

Diagnosis 3: Check chrony Sources
----------------------------------
On each VM:
```bash
chronyc sources
```

Analyze output:
```
^* ipa.home.lab        2   6    17    4   -123us[ -456us] +/-   15ms
^- 162.159.200.1       2   6    17    4    +2ms[  +2ms]   +/-   50ms
```

Key indicators:
- ^* = Currently selected source (GOOD if pointing to IPA)
- ^+ = Acceptable alternative source
- ^- = Not selected (too much offset)
- ^? = Unreachable or untrusted

Problematic output (multiple sources fighting):
```
^? ipa.home.lab        0   0     0     -      +0ns[   +0ns] +/-    0ns
^* 162.159.200.1       2   6    17    4    +2ms[  +2ms]   +/-   50ms
^- pool.ntp.org        2   6    17    4    +5ms[  +5ms]   +/-  100ms
```

This shows VM syncing to external NTP instead of IPA

Diagnosis 4: Check chrony Tracking
-----------------------------------
```bash
chronyc tracking
```

Good output:
```
Reference ID    : 0A001490 (ipa.home.lab)
Stratum         : 3
System time     : 0.000123 seconds slow of NTP time
Last offset     : -0.000456 seconds
RMS offset      : 0.001234 seconds
```

Bad output:
```
Reference ID    : 00000000 (127.0.0.1)
System time     : 30.123456 seconds fast of NTP time  ← PROBLEM
Last offset     : +15.000000 seconds                  ← LARGE OFFSET
```

Diagnosis 5: Test Kerberos Authentication
------------------------------------------
```bash
# Attempt to get ticket
kinit admin

# If fails with clock skew:
klist -v
# Check if ticket is present but invalid

# Check time difference
ssh ipa.home.lab "date +%s" && date +%s
# Compare Unix timestamps (should be < 300 second difference)
```

Diagnosis 6: Check for Time Jumps
----------------------------------
Monitor for sudden time changes:
```bash
# On affected VM
watch -n 1 'date +"%T.%N"'
```

Watch for:
- Time jumping backward/forward
- Milliseconds resetting to 000
- Indicates VMware Tools or chrony making adjustments

================================================================================
SOLUTION
================================================================================

Complete Time Sync Hierarchy Configuration

STEP 1: Disable VMware Tools Time Sync (ALL VMs)
-------------------------------------------------
On EVERY VM (including IPA server):

```bash
# Disable VMware Tools time sync
vmware-toolbox-cmd timesync disable

# Verify disabled
vmware-toolbox-cmd timesync status
# Output: Disabled

# Make persistent across VM restarts
echo "disable_vmwtools_timesync: true" >> /etc/vmware-tools/tools.conf
```

Why this matters:
- VMware Tools and chrony conflict
- VMware Tools doesn't understand NTP hierarchy
- Creates constant time drift battle

STEP 2: Configure IPA Server Time Sync
---------------------------------------
IPA server syncs to external authoritative sources

```bash
# On IPA server
sudo vi /etc/chrony.conf
```

Configuration:
```
# Use direct IPs to prevent DNS dependency
# (IPA itself provides DNS, chicken-and-egg problem)
server 162.159.200.1 iburst  # Cloudflare time server
server 216.239.35.0 iburst   # Google time server

# Allow LAN clients to sync from this server
allow 10.0.20.0/24

# Enable rapid drift correction
makestep 1.0 3

# Ignore time from DHCP (if applicable)
# sourcedir /run/chrony-dhcp  # Comment this out
```

Restart and verify:
```bash
sudo systemctl restart chronyd

# Check sources
chronyc sources -v

# Should show:
# ^* next to external server (162.159.200.1 or 216.239.35.0)
# Means IPA is syncing to external source

# Check tracking
chronyc tracking
# Reference ID should match external server
```

STEP 3: Configure Client VMs Time Sync
---------------------------------------
All other VMs sync ONLY to IPA server

On each client VM (K8s nodes, Ansible, Monitoring, etc.):

```bash
sudo vi /etc/chrony.conf
```

Configuration:
```
# ONLY sync to IPA server
server ipa.home.lab iburst

# Comment out ALL other sources
# pool pool.ntp.org iburst        # ← Comment out
# server 0.rhel.pool.ntp.org iburst  # ← Comment out
# sourcedir /run/chrony-dhcp     # ← Comment out

# Enable rapid drift correction
makestep 1.0 3
```

Restart and force immediate sync:
```bash
sudo systemctl restart chronyd

# Force immediate time sync
sudo chronyc makestep

# Verify source
chronyc sources -v

# Should show:
# ^* ipa.home.lab  ← Client syncing to IPA
```

STEP 4: Verify Time Hierarchy
------------------------------
Correct NTP hierarchy:
```
Internet NTP Servers (Cloudflare, Google)
           ↓
      IPA Server (Stratum 3)
           ↓
   ┌────────┼────────┐
   ↓        ↓        ↓
K8s-Master Worker-1 Worker-2  (Stratum 4)
```

Verification commands:
```bash
# On IPA server
chronyc sources | grep "^\^*"
# Should show external server (162.159.200.1)

# On client VMs
chronyc sources | grep "^\^*"
# Should show ipa.home.lab
```

STEP 5: Use Ansible to Fix All Nodes (Recommended)
---------------------------------------------------
Create Ansible playbook to automate configuration:

```yaml
---
- name: Fix NTP Synchronization Hierarchy
  hosts: all
  become: yes
  tasks:
    - name: Disable VMware Tools time sync
      command: vmware-toolbox-cmd timesync disable
      changed_when: false

    - name: Configure chrony to sync to IPA
      lineinfile:
        path: /etc/chrony.conf
        regexp: '^server ipa.home.lab'
        line: 'server ipa.home.lab iburst'
        state: present
      when: inventory_hostname != 'ipa.home.lab'

    - name: Comment out external NTP sources
      replace:
        path: /etc/chrony.conf
        regexp: '^(server|pool) (?!ipa\.home\.lab)'
        replace: '# \1'
      when: inventory_hostname != 'ipa.home.lab'

    - name: Restart chronyd
      service:
        name: chronyd
        state: restarted

    - name: Force time sync
      command: chronyc makestep
      changed_when: false
```

Run playbook:
```bash
ansible-playbook -i inventory fix_ntp.yml
```

================================================================================
VERIFICATION
================================================================================

Verification 1: Check Time Sync Status (All VMs)
-------------------------------------------------
```bash
# Run on all VMs via Ansible
ansible all -i inventory -b -m command -a "chronyc sources"
```

Expected output for IPA server:
```
^* 162.159.200.1   ← External source
```

Expected output for clients:
```
^* ipa.home.lab    ← IPA server
```

Verification 2: Check Time Differences
---------------------------------------
```bash
# Collect timestamps from all VMs
ansible all -i inventory -m command -a "date +%s"
```

All timestamps should be within 1-2 seconds of each other

Verification 3: Test Kerberos Authentication
---------------------------------------------
On a client VM:
```bash
# Get ticket
kinit admin
# Should succeed without clock skew error

# Verify ticket
klist
# Should show valid ticket with future expiration

# Test IPA command
ipa user-find
# Should return results
```

Verification 4: Monitor for Drift Over Time
--------------------------------------------
```bash
# Check tracking on clients
ansible all -i inventory -b -m command -a "chronyc tracking"
```

Look for:
- "System time" offset < 0.1 seconds
- "Last offset" < 0.01 seconds
- Stable over multiple checks

Verification 5: Check VMware Tools Disabled
--------------------------------------------
```bash
ansible all -i inventory -m command -a "vmware-toolbox-cmd timesync status"
```

All should show: Disabled

================================================================================
TROUBLESHOOTING POST-FIX
================================================================================

If Time Still Drifting After Configuration:
--------------------------------------------

Issue 1: Large Initial Offset
If drift is >10 minutes, chrony won't correct automatically

Solution:
```bash
# Stop chrony
sudo systemctl stop chronyd

# Manually set time close to correct
sudo date -s "2025-12-25 12:00:00"

# Start chrony
sudo systemctl start chronyd

# Force sync
sudo chronyc makestep
```

Issue 2: Firewall Blocking NTP
NTP uses UDP port 123

Solution:
```bash
# On IPA server
sudo firewall-cmd --add-service=ntp --permanent
sudo firewall-cmd --reload

# Test from client
nc -vuz ipa.home.lab 123
```

Issue 3: DNS Not Resolving IPA
Client can't resolve ipa.home.lab

Solution:
```bash
# Test DNS
dig ipa.home.lab

# If fails, add to /etc/hosts temporarily
echo "10.0.20.184  ipa.home.lab" | sudo tee -a /etc/hosts

# Restart chronyd
sudo systemctl restart chronyd
```

Issue 4: ESXi Host Time Wrong
If ESXi host time is wrong, IPA may drift even with external NTP

Solution:
```bash
# SSH to ESXi host
esxcli system time set -d 25 -m 12 -y 2025 -H 12 -M 00

# Or configure ESXi NTP
esxcli system ntp set -s pool.ntp.org
esxcli system ntp set -e yes
```

================================================================================
PREVENTION & BEST PRACTICES
================================================================================

DO:
✅ Disable VMware Tools time sync on ALL VMs
✅ Create clear NTP hierarchy (Internet → IPA → Clients)
✅ Use single time source per VM
✅ Monitor time drift regularly
✅ Document time sync configuration
✅ Test Kerberos after time changes
✅ Use Ansible to enforce configuration

DON'T:
❌ Mix VMware Tools time sync with chrony
❌ Allow VMs to sync to multiple NTP sources
❌ Use DHCP-provided NTP servers
❌ Forget to test after configuration changes
❌ Ignore small time drifts (they accumulate)
❌ Configure client VMs to sync to external NTP (bypass IPA)

Architecture Decision:
----------------------
IPA Server = NTP Server for Internal Network

Why:
- Single source of truth for time
- Reduces external dependencies
- Kerberos requires time consistency
- Simplifies troubleshooting
- Production-like design

================================================================================
MONITORING
================================================================================

Automated Monitoring Script:
-----------------------------
```bash
#!/bin/bash
# /usr/local/bin/check_time_drift.sh

MAX_DRIFT_SECONDS=2

# Get IPA time
IPA_TIME=$(ssh ipa.home.lab "date +%s")

# Get local time
LOCAL_TIME=$(date +%s)

# Calculate drift
DRIFT=$((LOCAL_TIME - IPA_TIME))
ABS_DRIFT=${DRIFT#-}

if [ $ABS_DRIFT -gt $MAX_DRIFT_SECONDS ]; then
    echo "WARNING: Time drift detected: ${DRIFT}s from IPA"
    echo "Local: $(date)"
    echo "IPA:   $(ssh ipa.home.lab 'date')"
    exit 1
else
    echo "OK: Time drift within tolerance (${DRIFT}s)"
    exit 0
fi
```

Run via cron:
```bash
# Check every 15 minutes
*/15 * * * * /usr/local/bin/check_time_drift.sh
```

Ansible Monitoring Playbook:
-----------------------------
```yaml
---
- name: Check Time Drift Across Cluster
  hosts: all
  gather_facts: no
  tasks:
    - name: Get current timestamp
      command: date +%s
      register: node_time

    - name: Display time drift
      debug:
        msg: "{{ inventory_hostname }}: {{ node_time.stdout }}"

    - name: Calculate drift from IPA
      set_fact:
        time_drift: "{{ node_time.stdout | int - hostvars['ipa.home.lab'].node_time.stdout | int }}"

    - name: Alert if drift too large
      fail:
        msg: "Time drift {{ time_drift }}s exceeds threshold!"
      when: time_drift | abs > 5
```

================================================================================
REFERENCES
================================================================================
Source: /DC-K8s/.archive/.../01-Identity-FreeIPA/08-troubleshooting.md
Related Cases:
  - Other FreeIPA authentication issues
Kerberos Docs: Clock Skew Tolerance Configuration
chrony Docs: NTP Server Configuration
VMware KB: Disabling VMware Tools Time Synchronization

================================================================================
LESSONS LEARNED
================================================================================
- Kerberos is extremely time-sensitive (5-minute tolerance)
- VMware Tools time sync conflicts with guest OS NTP
- Always disable one time sync mechanism (preferably VMware Tools)
- NTP hierarchy prevents split-brain time scenarios
- Small drifts accumulate into authentication failures
- Automation (Ansible) ensures consistent configuration
- Monitoring detects drift before it causes outages
- Time sync is often overlooked but critical for authentication
- "Intermittent auth failures" often means time drift
- Test Kerberos auth after ANY time configuration change
