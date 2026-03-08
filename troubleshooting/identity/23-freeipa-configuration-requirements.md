# TS-007: FreeIPA Configuration Requirements and Gotchas

**Date:** 2026-03-05
**Environment:** DEV (lab.local)
**Affected Systems:** FreeIPA server
**Status:** RESOLVED

This document covers multiple configuration requirements discovered during FreeIPA setup.

---

## Issue 1: Password Policy Requires cospriority

### Symptom

```
TASK [Set password policy for automation users (4 years)]
fatal: [freeipa.lab.local]: FAILED! => "msg": "pwpolicy_add: automation_users: 'cospriority' is required"
```

### Root Cause

When creating **group-based** password policies, FreeIPA requires `cospriority` (Class of Service Priority) to determine which policy applies when a user belongs to multiple groups.

### Solution

Add `cospriority` to password policy tasks. Lower number = higher priority.

```yaml
- name: Set password policy for automation users (4 years)
  freeipa.ansible_freeipa.ipapwpolicy:
    ipaadmin_principal: "{{ ipaadmin_principal }}"
    ipaadmin_password: "{{ ipaadmin_password }}"
    name: automation_users
    maxlife: 1460          # days
    cospriority: 10        # Higher priority (lower number)

- name: Set password policy for admin users (1 year)
  freeipa.ansible_freeipa.ipapwpolicy:
    ipaadmin_principal: "{{ ipaadmin_principal }}"
    ipaadmin_password: "{{ ipaadmin_password }}"
    name: admin_users
    maxlife: 360           # days
    cospriority: 20        # Lower priority (higher number)
```

### Simple Explanation

If a user belongs to both `automation_users` and `admin_users`, which password policy applies? The one with the **lowest cospriority number wins**.

---

## Issue 2: FreeIPA Server Doesn't Use SSSD for Sudo

### Symptom

```bash
# On FreeIPA server - FAILS
ansible freeipa -m command -a "id -u"
# freeipa.lab.local | FAILED | rc=-1 >> Missing sudo password

# Check sudo rules
sudo -l -U super_bot
# User super_bot is not allowed to run sudo on freeipa.

# But on IPA clients - WORKS
ansible managed_hosts -m command -a "id -u"
# All return 0
```

### Root Cause

The FreeIPA **server** is the identity provider, not a client. It does not use SSSD to look up sudo rules. SSSD-based sudo only works on IPA **clients**.

```
FreeIPA Server                    IPA Clients
┌─────────────────┐              ┌─────────────────┐
│ Stores rules    │              │ SSSD queries    │
│ Does NOT apply  │              │ FreeIPA for     │
│ rules to itself │              │ sudo rules      │
└─────────────────┘              └─────────────────┘
```

### Solution

Manage the FreeIPA server separately with direct root access.

```ini
# inventory.ini
[freeipa]
freeipa.lab.local ansible_user=root

[managed_hosts:children]
k8s_masters
k8s_workers
vault_cluster
ansible
local_runners
nginx

[managed_hosts:vars]
ansible_user=super_bot
ansible_become=yes
ansible_become_method=sudo
```

Use different host groups for different operations:
- `ansible managed_hosts ...` - Normal operations via super_bot + sudo
- `ansible freeipa ...` - IPA server management via root

### Simple Explanation

Think of FreeIPA as the security office that issues access badges. The security office itself doesn't use badges - guards just work there. IPA clients are like other buildings that check badges issued by the security office.

---

## Issue 3: UID Range Must Be Above UID_MAX

### Symptom

```
TASK [freeipa.ansible_freeipa.ipaserver]
fatal: "ipaserver_idstart must be larger than UID_MAX"
```

### Root Cause

Linux systems have a `UID_MAX` setting (default 60000) in `/etc/login.defs`. FreeIPA requires its UID range to start **above** this value to prevent conflicts with local users.

```bash
grep UID_MAX /etc/login.defs
# UID_MAX    60000
```

### Solution

Set FreeIPA UID range above UID_MAX:

```yaml
# In freeipa_setup.yml
vars:
  # Must be > UID_MAX (60000)
  # Must be < 65536 for LXC unprivileged containers
  ipaserver_idstart: 60001
  ipaserver_idmax: 65500
```

### Why the Upper Limit?

See [TS-005](TS-005_LXC_UID_Mapping_initgroups_Error.md) for why we keep it below 65536 (LXC unprivileged container compatibility).

### Simple Explanation

Linux reserves UIDs 0-60000 for local users (created with `useradd`). FreeIPA must use UIDs above this range so there's no confusion between "local user bob" and "FreeIPA user bob".

---

## Summary Table

| Issue | Error | Fix |
|-------|-------|-----|
| Password Policy | `'cospriority' is required` | Add `cospriority: <number>` |
| Server Sudo | `Missing sudo password` | Use `ansible_user=root` for freeipa host |
| UID Range | `must be larger than UID_MAX` | Set `ipaserver_idstart: 60001` |

---

## References

- [FreeIPA Password Policies](https://freeipa.readthedocs.io/en/latest/designs/password-policy.html)
- [FreeIPA SUDO Integration](https://freeipa.readthedocs.io/en/latest/designs/sudo.html)
- [Linux UID/GID Ranges](https://man7.org/linux/man-pages/man5/login.defs.5.html)
