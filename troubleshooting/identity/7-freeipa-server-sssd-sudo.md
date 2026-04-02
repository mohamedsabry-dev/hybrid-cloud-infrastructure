# Case 7: FreeIPA Server Doesn't Use SSSD for Sudo

**Component:** FreeIPA | SSSD | Sudo
**Date:** March 2026

---

## Symptom

```bash
# On FreeIPA server
ansible freeipa -m command -a "id -u"
freeipa.lab.local | FAILED | rc=-1 >> Missing sudo password

# Checking sudo rules shows nothing
sudo -l -U super_bot
User super_bot is not allowed to run sudo on freeipa.
```

But all other hosts (IPA clients) work fine with the same user.

---

## Root Cause

The FreeIPA **server** (IPA master) is the identity provider, not a client. It does not use SSSD for sudo lookups - sudo rules via SSSD only apply to IPA **clients**.

---

## Verification

```bash
# Host is in the hostgroup
ipa hostgroup-show automation_group
# Shows freeipa.lab.local as member

# Sudo rule exists
ipa sudorule-show super_bot
# Shows correct configuration

# But SSSD doesn't apply it on the server itself
sudo -l -U super_bot
# "not allowed to run sudo"
```

---

## Solution

Manage the FreeIPA server separately with root access in inventory:

```ini
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

---

## Lesson

- Use `ansible managed_hosts` for normal operations (domain user with sudo)
- Use `ansible freeipa` for IPA server management (root user)
- FreeIPA server is always managed separately from its clients
