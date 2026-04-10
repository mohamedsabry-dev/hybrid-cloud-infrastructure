# TS-IDN-004 | 2026-03-05 | RESOLVED

## 1. Context
- System: FreeIPA
- Environment: DEV (lab.local)
- Related components: FreeIPA server, password policies, user groups

## 2. Issue
- Symptom: Ansible task to create group-based password policy fails
- Error:
```
TASK [Set password policy for automation users (4 years)]
fatal: [freeipa.lab.local]: FAILED! => "msg": "pwpolicy_add: automation_users: 'cospriority' is required"
```

## 3. Analysis

**Check 1: What is the task trying to do?**
```yaml
- name: Set password policy for automation users (4 years)
  freeipa.ansible_freeipa.ipapwpolicy:
    ipaadmin_principal: "{{ ipaadmin_principal }}"
    ipaadmin_password: "{{ ipaadmin_password }}"
    name: automation_users
    maxlife: 1460
```
Finding: Creating a password policy for the `automation_users` group with 4-year expiry.

**Check 2: What is cospriority?**
```bash
# On FreeIPA server
ipa help pwpolicy
```
Finding: `cospriority` = Class of Service Priority. Required for group-based policies to determine precedence when user belongs to multiple groups.

**Check 3: Why is it required?**

FreeIPA has two types of password policies:
1. **Global policy** - applies to all users, no priority needed
2. **Group-based policy** - applies to group members, needs priority to resolve conflicts

If user `super_bot` belongs to both `automation_users` (4-year expiry) and `admin_users` (1-year expiry), which policy applies? The one with **lowest cospriority number wins**.

## 4. Root Cause
> Group-based password policies in FreeIPA require `cospriority` parameter. Without it, FreeIPA doesn't know how to prioritize when a user belongs to multiple groups with different policies.

## 5. Solution
> Add `cospriority` to all group-based password policy tasks.

**Why this works:** Lower number = higher priority. Setting different priorities ensures deterministic policy selection.

**File:** `ansible/dev/playbooks/freeipa/domain_config.yml`

**Location:** On FreeIPA server (freeipa.lab.local)

**Before (broken):**
```yaml
- name: Set password policy for automation users (4 years)
  freeipa.ansible_freeipa.ipapwpolicy:
    ipaadmin_principal: "{{ ipaadmin_principal }}"
    ipaadmin_password: "{{ ipaadmin_password }}"
    name: automation_users
    maxlife: 1460
```

**After (working):**
```yaml
- name: Set password policy for automation users (4 years)
  freeipa.ansible_freeipa.ipapwpolicy:
    ipaadmin_principal: "{{ ipaadmin_principal }}"
    ipaadmin_password: "{{ ipaadmin_password }}"
    name: automation_users
    maxlife: 1460
    cospriority: 10        # Higher priority (lower number)

- name: Set password policy for admin users (1 year)
  freeipa.ansible_freeipa.ipapwpolicy:
    ipaadmin_principal: "{{ ipaadmin_principal }}"
    ipaadmin_password: "{{ ipaadmin_password }}"
    name: admin_users
    maxlife: 360
    cospriority: 20        # Lower priority (higher number)
```

**Verification:**
```bash
# On FreeIPA server
ipa pwpolicy-show automation_users
  Group: automation_users
  Max lifetime (days): 1460
  Priority: 10

ipa pwpolicy-show admin_users
  Group: admin_users
  Max lifetime (days): 360
  Priority: 20
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact: None - just setting required parameter

## 7. Impact After Fix
- Observed: Password policies created successfully
- No new issues caused

## 8. Notes
- Global password policy (default) doesn't need cospriority
- Only group-based policies require it
- Plan your priority numbers with gaps (10, 20, 30...) so you can insert new policies later

## 9. Workaround (if any)
> N/A - must provide cospriority for group-based policies.
