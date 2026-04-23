# TS-IDN-005 | 2026-03-05 | WORKAROUND APPLIED
_____________________________________________________________________

[Info]
Domain: Identity / FreeIPA
Sub-techs: FreeIPA, SSSD, sudo rules, Ansible inventory
Environment: DEV lab.local | FreeIPA server freeipa.lab.local | all IPA clients
Re-opened: No

_____________________________________________________________________

[Issue Description]
Sudo rules work correctly on all IPA clients but not on the FreeIPA server itself.
Ansible fails when targeting freeipa.lab.local with super_bot + sudo.

  # On FreeIPA server — FAILS
  ansible freeipa -m command -a "id -u"
  freeipa.lab.local | FAILED | rc=-1 >> Missing sudo password

  sudo -l -U super_bot (on freeipa)
  User super_bot is not allowed to run sudo on freeipa.

  # On IPA clients — WORKS
  ansible managed_hosts -m command -a "id -u"
  vault1.lab.local | CHANGED | rc=0 >> 0
  k8s-master1.lab.local | CHANGED | rc=0 >> 0

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
First confirmed the sudo rule and hostgroup are configured correctly —
ruled out a misconfiguration before digging deeper.

Command:
  ipa hostgroup-show automation_group
  ipa sudorule-show super_bot

Output:
  automation_group members: freeipa.lab.local, vault1.lab.local, vault2.lab.local...
  sudo rule: enabled, user=super_bot, hostgroup=automation_group, command=all, runas=root

freeipa.lab.local is in the hostgroup and the rule looks correct.
So the rule exists and is configured right — problem is elsewhere.

Command:
  cat /etc/nsswitch.conf | grep sudoers  (on freeipa server)

Output:
  sudoers: files sss

SSSD is running on the FreeIPA server, but checking sudo on an IPA client confirmed
the same rule works fine there with the same user.


# Suspected Root Cause
FreeIPA server does not apply its own sudo rules to itself via SSSD — it is the
identity provider, not a client, so SSSD-based sudo resolution does not work on
the server itself.

NOTE: This theory has evidence working against it. In the old POC environment,
FreeIPA was managed via a domain user (super_ansible) using the same sudo approach
and it worked without issues:

  Old inventory (working):
    [ansible]
    ansible.home.lab ansible_connection=local

    [ipa]
    ipa.home.lab

    [all:vars]
    ansible_user=super_ansible

IPA was managed under super_ansible with no sudo failures at that time.
This means the suspected root cause may not be the full picture. The real root
cause is not fully confirmed — could be related to differences in SSSD config,
sudo rule setup, or domain enrollment between old and new environments.
Not investigated further at this time.


# More Checks Notes:
Compared behavior between freeipa server and vault1 (IPA client) with same user and rule.

Command:
  sudo -l -U super_bot  (on vault1)

Output:
  User super_bot may run the following commands on vault1:
    (root) NOPASSWD: ALL

Same user, same rule — works on client, not on server.


# Suspected Solution
Manage FreeIPA server separately in Ansible inventory using root directly.
Bypass the unconfirmed sudo issue rather than spending more time on root cause.


# Test
Updated inventory to use ansible_user=root for freeipa group, re-ran Ansible.

Command:
  ansible freeipa -m command -a "id -u"
  ansible managed_hosts -m command -a "id -u"

Result: PASS — freeipa returns 0 via root, all managed_hosts return 0 via super_bot + sudo.

_____________________________________________________________________

[Final Root Cause]
Not fully confirmed. Suspected: FreeIPA server not resolving sudo rules via SSSD
for domain users in this environment. However this conflicts with old POC evidence
where the same approach worked fine under super_ansible. Differences between old
and new environment were not fully investigated. Workaround applied instead.

_____________________________________________________________________

[Final Solution]
Workaround — separated FreeIPA server from managed hosts in Ansible inventory.
FreeIPA server uses root directly, all IPA clients use super_bot + sudo.

  ansible/dev/inventory/inventory.ini:

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

Verified: Yes (workaround confirmed working, root cause not fully resolved)

_____________________________________________________________________

[Risk Level] LOW
Note: FreeIPA server accessed as root — acceptable since it is the identity master
and requires privileged access regardless.

_____________________________________________________________________

[References]
- archive-poc-v1/automation/ansible/ipa
- archive-poc-v1/automation/ansible/inventory

_____________________________________________________________________

[Draft Notes]

Root cause remains open. If sudo via domain user on FreeIPA server becomes needed
in the future, investigate:
  - SSSD configuration differences between old POC and current lab
  - How domain enrollment was done on the FreeIPA server itself
  - Sudo rule and group membership resolution on the server
  - We can compare the config of old poc ipa archive-poc-v1/automation/ansible/ipa with the current config ansible/dev/playbooks/freeipa && ansible/dev/inventory/inventory.ini

Current working pattern:
  ansible freeipa        → root directly
  ansible managed_hosts  → super_bot + sudo (IPA clients)