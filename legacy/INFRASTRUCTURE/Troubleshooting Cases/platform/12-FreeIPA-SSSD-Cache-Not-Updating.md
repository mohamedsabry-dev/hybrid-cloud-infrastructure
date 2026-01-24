================================================================================
CASE: FreeIPA SSSD Cache Not Updating - Changes Not Taking Effect
================================================================================
Category: Platform - FreeIPA / SSSD Caching
Severity: Medium
Date: Post-Configuration / Runtime
Environment: FreeIPA Server, SSSD Clients
Issue: HBAC/sudo rule changes, user/group modifications not reflecting on clients

================================================================================
SYMPTOM
================================================================================
- Created new HBAC rule in IPA, but user still can't login to client
- Added user to group in IPA, but group membership doesn't show on client
- Modified sudo rule in IPA, but sudo permissions unchanged on client
- Deleted user in IPA, but user still exists on client
- Changes visible in IPA web UI but not on client systems

Example Scenarios:

Scenario 1: SSH Access
-----------------------
```bash
# On IPA server - Add user to admins group
ipa group-add-member admins --users=user1

# On client - User still not in group
ssh user1@client.home.lab "id"
# Output: uid=1001(user1) gid=1001(user1) groups=1001(user1)
# Missing: admins group membership
```

Scenario 2: Sudo Access
------------------------
```bash
# On IPA server - Create sudo rule for user
ipa sudorule-add admin_full
ipa sudorule-add-user admin_full --users=user1
ipa sudorule-mod admin_full --cmdcat=all

# On client - Sudo still denied
ssh user1@client "sudo whoami"
# Error: user1 is not in the sudoers file
```

Scenario 3: Deleted User Persists
----------------------------------
```bash
# On IPA server - Delete user
ipa user-del olduser

# On client - User still exists
id olduser
# Output: uid=1234(olduser) gid=1234(olduser) groups=1234(olduser)
```

================================================================================
ROOT CAUSE
================================================================================
SSSD (System Security Services Daemon) caches user, group, and policy
information from IPA to reduce network queries and improve performance.
Changes made in IPA are not immediately reflected on clients.

SSSD Caching Behavior:
-----------------------
1. Client queries IPA for user/group/policy
2. SSSD stores result in local cache (/var/lib/sss/db/)
3. Subsequent queries use cache instead of contacting IPA
4. Cache entries have TTL (time-to-live), typically:
   - User cache: 5400 seconds (90 minutes)
   - Group cache: 300 seconds (5 minutes)
   - Sudo rules: 21600 seconds (6 hours)
   - HBAC rules: 300 seconds (5 minutes)

5. Until cache expires, client uses stale data

Cache Hit vs Cache Miss:
------------------------
Cache HIT (Fast but may be stale):
  User logs in → SSSD checks cache → User found → Use cached data

Cache MISS (Slow but current):
  User logs in → SSSD checks cache → User not found → Query IPA → Cache result

Problem:
- After IPA changes, existing cache entries remain valid (TTL not expired)
- Client continues using old cached data
- Changes appear to "not work" even though IPA is correct

Why SSSD Uses Caching:
-----------------------
- Performance: Avoid constant LDAP queries for every auth
- Resilience: Work offline if IPA temporarily unavailable
- Scalability: Reduce load on IPA server
- Speed: Sub-millisecond cache lookups vs 10-100ms LDAP queries

Trade-off:
- Fast performance ↔ Delayed propagation of changes

================================================================================
DIAGNOSTIC PROCEDURES
================================================================================

Diagnosis 1: Verify Change Exists in IPA
-----------------------------------------
First confirm the change is actually in IPA:

```bash
# On IPA server
kinit admin

# Check user exists
ipa user-show user1

# Check group membership
ipa group-show admins
# Look for user1 in "Member users" list

# Check HBAC rules
ipa hbacrule-show allow_admins
# Verify user/group is in rule

# Check sudo rules
ipa sudorule-show admin_full
# Verify rule configuration
```

If change NOT in IPA → Fix IPA configuration first
If change IS in IPA → Problem is client-side caching

Diagnosis 2: Check SSSD Domain Status
--------------------------------------
On client VM:
```bash
# Check SSSD connection to IPA
sudo sssctl domain-status home.lab
```

Good output:
```
Online status: Online
Active servers:
IPA: ipa.home.lab
```

Bad output:
```
Online status: Offline  ← Problem, can't sync from IPA
```

If offline → Check network, DNS, firewall

Diagnosis 3: Check When Cache Was Last Updated
-----------------------------------------------
```bash
# Check cache timestamps
sudo ls -l /var/lib/sss/db/

# Check domain status with timestamps
sudo sssctl domain-status home.lab
```

Output shows:
```
Last update: Wed Dec 25 10:30:00 2025  ← If hours old, cache is stale
```

Diagnosis 4: Check User in Cache
---------------------------------
```bash
# Check specific user in cache
sudo sssctl user-checks user1

# More detailed
sudo sssctl user-show user1
```

Output shows cached attributes (may be stale)

Diagnosis 5: Check SSSD Logs
-----------------------------
```bash
# Enable debug logging (if needed)
sudo vi /etc/sssd/sssd.conf
# Add under [domain/home.lab]:
# debug_level = 6

# Restart SSSD
sudo systemctl restart sssd

# Watch logs
sudo tail -f /var/log/sssd/sssd_home.lab.log

# Look for cache expiration messages
```

================================================================================
SOLUTIONS
================================================================================

Solution 1: Clear SSSD Cache (Soft - Recommended)
--------------------------------------------------
Forces cache refresh without disrupting service

```bash
# Clear all cache entries
sudo sss_cache -E

# Wait 2-3 seconds for background refresh
sleep 3

# Test change
id user1
# Should now show updated group membership

# Or test sudo
sudo -l -U user1
# Should show updated sudo permissions
```

Alternative: Clear specific entries
```bash
# Clear specific user
sudo sss_cache -u username

# Clear specific group
sudo sss_cache -g groupname

# Clear all users
sudo sss_cache -U

# Clear all groups
sudo sss_cache -G
```

Solution 2: Restart SSSD Service (Medium)
------------------------------------------
Clears cache and forces full reload

```bash
# Restart SSSD
sudo systemctl restart sssd

# Wait for service startup
sleep 5

# Verify service running
sudo systemctl status sssd

# Test change
id user1
```

Note: May cause brief authentication delay during restart

Solution 3: Reboot Client (Hard)
---------------------------------
Forces complete system refresh

```bash
# Reboot client
sudo reboot

# After reboot, test
id user1
```

Most reliable but causes downtime

Solution 4: Use Ansible to Clear Cache on All Clients
------------------------------------------------------
Apply fix across entire infrastructure

Create playbook: clear_sssd_cache.yml
```yaml
---
- name: Clear SSSD Cache on All Clients
  hosts: all
  become: yes
  tasks:
    - name: Clear SSSD cache
      command: sss_cache -E
      changed_when: true

    - name: Wait for cache refresh
      pause:
        seconds: 3

    - name: Verify SSSD status
      command: sssctl domain-status home.lab
      register: sssd_status

    - name: Display SSSD status
      debug:
        var: sssd_status.stdout_lines
```

Run playbook:
```bash
ansible-playbook -i inventory clear_sssd_cache.yml
```

Solution 5: Reduce Cache TTL (Prevention)
------------------------------------------
Make cache expire faster (reduces staleness)

Edit /etc/sssd/sssd.conf on clients:
```ini
[domain/home.lab]
# Reduce cache timeouts (seconds)
entry_cache_timeout = 300           # Default: 5400 (90 min) → 5 min
entry_cache_user_timeout = 300      # Default: 5400
entry_cache_group_timeout = 180     # Default: 300 (5 min) → 3 min
entry_cache_sudo_timeout = 600      # Default: 21600 (6 hours) → 10 min
```

Restart SSSD:
```bash
sudo systemctl restart sssd
```

Trade-off:
- Faster change propagation
- More frequent LDAP queries to IPA
- Slightly higher network traffic
- Slightly slower authentication (cache misses)

For lab environments: Acceptable
For production: Tune based on change frequency

================================================================================
VERIFICATION
================================================================================

Verification 1: Check User Group Membership
--------------------------------------------
```bash
# On client
id user1

# Should show:
# uid=1001(user1) gid=1001(user1) groups=1001(user1),10001(admins)
#                                                        ↑ Updated!
```

Verification 2: Test SSH Access with HBAC
------------------------------------------
```bash
# From your laptop
ssh user1@client.home.lab

# Should either:
# - Successfully connect (if HBAC allows)
# - Show "Permission denied" immediately (if HBAC denies)

# NOT: Hang or show stale behavior
```

Verification 3: Test Sudo Access
---------------------------------
```bash
ssh user1@client.home.lab "sudo whoami"

# Should show:
# root  ← If sudo rule applied correctly

# NOT:
# Sorry, user user1 may not run sudo  ← Stale cache
```

Verification 4: Verify Deleted User Gone
-----------------------------------------
```bash
# After clearing cache
id deleteduser

# Should show:
# id: 'deleteduser': no such user  ← Correct

# NOT show user details (stale cache)
```

Verification 5: Check SSSD Cache Timestamp
-------------------------------------------
```bash
sudo sssctl domain-status home.lab
```

Look for:
```
Last update: Wed Dec 25 12:00:00 2025  ← Recent timestamp
```

If timestamp is recent (within minutes), cache is fresh

================================================================================
TROUBLESHOOTING EDGE CASES
================================================================================

Issue 1: Cache Clear Doesn't Help
----------------------------------
Symptom: Still seeing stale data after sss_cache -E

Possible causes:
1. SSSD not reloading cache
2. nsswitch.conf misconfigured
3. Application-level caching

Solutions:
```bash
# Check nsswitch.conf uses sss
grep sss /etc/nsswitch.conf
# Should show:
# passwd: files sss
# group:  files sss

# Hard restart SSSD
sudo systemctl stop sssd
sudo rm -rf /var/lib/sss/db/*  # DELETE cache files
sudo systemctl start sssd
```

Issue 2: Cache Clears But Repopulates with Stale Data
------------------------------------------------------
Symptom: Cache refresh pulls old data from IPA

Cause: IPA replication lag (multi-master setup)

Solution:
```bash
# On IPA server, check replication status
ipa-replica-manage list
kinit admin
ipa-replica-manage list-ruv

# Force replication
ipa-replica-manage force-sync --from=ipa1.home.lab
```

Issue 3: Some Users Update, Others Don't
-----------------------------------------
Symptom: Selective cache updates

Cause: Cache entries have different TTLs

Solution:
```bash
# Clear ALL cache, not just users
sudo sss_cache -E  # Everything
# NOT just: sudo sss_cache -U  # Only users
```

Issue 4: SSSD Offline Mode
---------------------------
Symptom: Cache won't refresh even after clear

Cause: SSSD thinks IPA is unreachable

Diagnosis:
```bash
sudo sssctl domain-status home.lab
# Check: Online status: Offline  ← Problem
```

Solutions:
```bash
# Test IPA connectivity
ping ipa.home.lab
nslookup ipa.home.lab

# Check firewall
sudo firewall-cmd --list-all

# Restart SSSD to retry connection
sudo systemctl restart sssd
```

================================================================================
PREVENTION & BEST PRACTICES
================================================================================

DO:
✅ Clear SSSD cache after making IPA changes
✅ Use Ansible to clear cache on all clients simultaneously
✅ Reduce cache TTL in lab environments
✅ Test changes on one client before assuming cluster-wide
✅ Document cache behavior in runbooks
✅ Set expectations: Changes take 1-5 minutes to propagate
✅ Monitor SSSD online/offline status

DON'T:
❌ Expect instant propagation of IPA changes
❌ Assume cache clears automatically
❌ Delete /var/lib/sss/db/ while SSSD is running (corrupts cache)
❌ Set cache TTL too low (<60 seconds) in production
❌ Ignore SSSD offline status
❌ Restart SSSD during active user sessions (may disconnect users)

Operational Workflow:
---------------------
1. Make change in IPA
2. Clear SSSD cache on affected clients
3. Wait 3-5 seconds
4. Test change
5. If doesn't work, check IPA first (not always cache issue)

Ansible Workflow:
-----------------
1. Run IPA playbook (creates users, groups, rules)
2. Run cache clear playbook automatically
3. Run verification playbook
4. All automated, consistent

================================================================================
AUTOMATION EXAMPLES
================================================================================

Playbook: IPA User Creation with Cache Clear
---------------------------------------------
```yaml
---
- name: Create IPA User and Clear Client Cache
  hosts: localhost
  connection: local
  tasks:
    - name: Create user in IPA
      ipauser:
        name: newuser
        first: New
        last: User
        password: SecurePassword123
        state: present

    - name: Add user to group
      ipagroup:
        name: admins
        user:
          - newuser
        state: present

- name: Clear SSSD cache on all clients
  hosts: clients
  become: yes
  tasks:
    - name: Clear cache
      command: sss_cache -E

    - name: Verify user visible
      command: id newuser
      register: user_check
      retries: 3
      delay: 5
      until: user_check.rc == 0
```

Monitoring Script:
------------------
```bash
#!/bin/bash
# /usr/local/bin/check_sssd_cache_age.sh

MAX_AGE_HOURS=1

CACHE_AGE=$(sudo sssctl domain-status home.lab | grep "Last update" | awk -F': ' '{print $2}')
CACHE_TIMESTAMP=$(date -d "$CACHE_AGE" +%s)
CURRENT_TIMESTAMP=$(date +%s)
AGE_SECONDS=$((CURRENT_TIMESTAMP - CACHE_TIMESTAMP))
AGE_HOURS=$((AGE_SECONDS / 3600))

if [ $AGE_HOURS -gt $MAX_AGE_HOURS ]; then
    echo "WARNING: SSSD cache is ${AGE_HOURS} hours old"
    echo "Last update: $CACHE_AGE"
    exit 1
else
    echo "OK: SSSD cache is recent (${AGE_HOURS} hours old)"
    exit 0
fi
```

================================================================================
REFERENCES
================================================================================
Source: /DC-K8s/.archive/.../01-Identity-FreeIPA/08-troubleshooting.md
Related Cases:
  - 11-FreeIPA-Time-Sync-Clock-Skew.txt (authentication issues)
SSSD Docs: Cache Management
FreeIPA Docs: Client Configuration
Red Hat Docs: SSSD Troubleshooting Guide

================================================================================
LESSONS LEARNED
================================================================================
- SSSD caching is a feature, not a bug (performance vs freshness trade-off)
- Always clear cache after IPA configuration changes
- Cache TTL defaults favor performance over instant updates
- Lab environments can use shorter TTLs than production
- Automation (Ansible) ensures consistent cache management
- "Changes not working" often means "cache not cleared"
- Users expect instant changes, but caching introduces delay
- Document expected propagation delay in operations runbooks
- Testing on one client before cluster-wide rollout catches issues early
- SSSD offline mode silently prevents cache refresh (monitor online status)
