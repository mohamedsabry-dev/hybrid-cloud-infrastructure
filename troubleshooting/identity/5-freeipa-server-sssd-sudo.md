# TS-IDN-005 | 2026-03-05 | RESOLVED

## 1. Context
- System: FreeIPA / SSSD / Sudo
- Environment: DEV (lab.local)
- Related components: FreeIPA server, sudo rules, Ansible inventory

## 2. Issue
- Symptom: Sudo rules work on IPA clients but not on FreeIPA server itself
- Error:
```bash
# On FreeIPA server - FAILS
[root@ansible dev]# ansible freeipa -m command -a "id -u"
freeipa.lab.local | FAILED | rc=-1 >> Missing sudo password

# Check sudo rules on FreeIPA server
[root@freeipa ~]# sudo -l -U super_bot
User super_bot is not allowed to run sudo on freeipa.

# But on IPA clients - WORKS
[root@ansible dev]# ansible managed_hosts -m command -a "id -u"
vault1.lab.local | CHANGED | rc=0 >> 0
k8s-master1.lab.local | CHANGED | rc=0 >> 0
# All return 0
```

## 3. Analysis

**Check 1: Is the host in the hostgroup?**
```bash
# On FreeIPA server
ipa hostgroup-show automation_group
  Host-group: automation_group
  Member hosts: freeipa.lab.local, vault1.lab.local, vault2.lab.local...
```
Finding: freeipa.lab.local IS in the hostgroup.

**Check 2: Does the sudo rule exist?**
```bash
# On FreeIPA server
ipa sudorule-show super_bot
  Rule name: super_bot
  Enabled: TRUE
  User: super_bot
  Host Groups: automation_group
  Command category: all
  RunAs User: root
```
Finding: Sudo rule exists and looks correct.

**Check 3: Why doesn't it apply on FreeIPA server?**
```bash
# On FreeIPA server - check SSSD status
systemctl status sssd
# sssd is running

# But check how sudo is configured
cat /etc/nsswitch.conf | grep sudoers
sudoers: files sss
```
Finding: SSSD is running, but FreeIPA server doesn't query itself via SSSD for sudo rules.

**Check 4: Compare with IPA client**
```bash
# On vault1 (IPA client)
sudo -l -U super_bot
User super_bot may run the following commands on vault1:
    (root) NOPASSWD: ALL
```
Finding: Same user, same rule - works on client, not on server.

## 4. Root Cause
> The FreeIPA **server** is the identity provider, not a client. It stores the rules but does NOT apply them to itself via SSSD. SSSD-based sudo only works on IPA **clients**.

```
FreeIPA Server                    IPA Clients
┌─────────────────┐              ┌─────────────────┐
│ Stores rules    │              │ SSSD queries    │
│ Does NOT apply  │ ──────────── │ FreeIPA for     │
│ rules to itself │              │ sudo rules      │
└─────────────────┘              └─────────────────┘
```

**Analogy:** FreeIPA server is like the security office that issues access badges. The security office itself doesn't use badges to get in - guards just work there. IPA clients are like other buildings that check badges issued by the security office.

## 5. Solution
> Manage FreeIPA server separately with direct root access in Ansible inventory.

**Why this works:** Since FreeIPA server can't use its own sudo rules via SSSD, we bypass this by using root directly for FreeIPA operations.

**File:** `ansible/dev/inventory/inventory.ini`

**Location:** Ansible control node inventory configuration

**Configuration:**
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

**Usage:**
```bash
# Normal operations - domain user with sudo (works on IPA clients)
ansible managed_hosts -m ping

# FreeIPA server management - root directly
ansible freeipa -m ping
```

**Verification:**
```bash
[root@ansible dev]# ansible freeipa -m command -a "id -u"
freeipa.lab.local | CHANGED | rc=0 >> 0

[root@ansible dev]# ansible managed_hosts -m command -a "id -u"
# All succeed via super_bot + sudo
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact: FreeIPA server accessed as root - acceptable since it's the identity master and requires privileged access anyway

## 7. Impact After Fix
- Observed: All Ansible operations work correctly
- FreeIPA managed via root, clients managed via domain user + sudo
- No new issues caused

## 8. Notes
- FreeIPA server is always managed separately from its clients
- This is by design, not a bug
- If you try to "fix" this by enrolling FreeIPA as its own client, you'll break things

## 9. Workaround (if any)
> N/A - this IS the solution. FreeIPA server must be managed differently from clients.

## References
- [FreeIPA SUDO Integration](https://freeipa.readthedocs.io/en/latest/designs/sudo.html)
