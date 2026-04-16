# TS-IDN-009 | 2026-04-15 | RESOLVED
# NOTE: Duplicate ID — this ticket conflicts with TS-IDN-009 (2026-03-20 keytab case).
# Needs renumbering before filing.
_____________________________________________________________________

[Info]
Domain: Identity / FreeIPA
Sub-techs: SSSD, SSH KnownHostsCommand, sss_ssh_knownhosts, Ansible, FreeIPA SSH config
Environment: DEV lab.local | Ansible control node | all managed hosts
Re-opened: No

_____________________________________________________________________

[Issue Description]
Ansible ad-hoc commands and playbooks take 28-34 seconds to execute when FreeIPA
is down. Direct SSH and raw module are fast — only Python-based modules are slow.

Discovered during IPA Domain Down DR Test (Part 2).

  raw module  → 0.7s   (fast)
  ping module → 34s    (slow)
  direct ssh  → 1.2s   (fast)

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
First suspected Python interpreter discovery since raw (no Python) was fast
and ping (uses Python) was slow.

Command:
  time ansible 10.0.64.10 -m ping -e 'ansible_python_interpreter=/usr/bin/python3'

Output:
  real 0m28.253s — still slow. Python interpreter discovery is not the cause.

Tested direct SSH:

Command:
  time ssh root@10.0.64.10 'hostname'

Output:
  real 0m1.2s — fast. Issue is Ansible-specific, not SSH itself.

Tested disabling Kerberos/GSSAPI and destroying tickets:

Command:
  ansible_ssh_common_args='-o PreferredAuthentications=publickey'
  kdestroy then re-run

Output:
  Still ~28 seconds both times. Not Kerberos, not GSSAPI.

Ran full verbose output to find what is different between Ansible SSH and direct SSH:

Command:
  time ansible 10.0.64.10 -m ping -vvvv

Output (critical finding):
  debug3: KnownHostsCommand-ORDER "/usr/bin/sss_ssh_knownhosts 10.0.64.10" pid 4948
  debug3: KnownHostsCommand-HOSTNAME "/usr/bin/sss_ssh_knownhosts 10.0.64.10" pid 4949

This is configured by FreeIPA in /etc/ssh/ssh_config.d/04-ipa.conf:
  KnownHostsCommand /usr/bin/sss_ssh_knownhosts %H


Background — what is known_hosts and why did this happen:

  When you SSH to a machine for the first time SSH asks "do you trust this host?"
  When you say yes, SSH saves that machine's fingerprint in ~/.ssh/known_hosts.
  Next connection it checks — same machine as before? Yes → connect silently.

  KnownHostsCommand is an override for this. Instead of checking the local file,
  SSH runs a command to dynamically fetch host keys. FreeIPA injects this during
  client enrollment — it tells SSH: ask sss_ssh_knownhosts instead, which asks
  SSSD, which asks FreeIPA, which has all host keys stored centrally.

  All hosts were manually accepted before (the "yes" prompt was answered for each).
  Those fingerprints are still saved in known_hosts on disk. But once FreeIPA
  sets KnownHostsCommand, SSH stops looking at the local file entirely and always
  goes to FreeIPA instead. The manual accepts are bypassed.

  This is fine when FreeIPA is up — SSSD responds instantly.
  When FreeIPA is down — sss_ssh_knownhosts tries to reach SSSD, SSSD tries to
  reach FreeIPA, gets no response, waits until timeout (~2s), then gives up.

Each SSH connection calls sss_ssh_knownhosts twice (ORDER + HOSTNAME).
When FreeIPA is down each call times out.

Ansible ping module makes 7-8 SSH connections per execution:
  get home dir, create temp dir, python discovery, platform info,
  sftp upload, chmod, execute module, cleanup

Delay calculation:
  7-8 SSH connections × 2 SSSD lookups × ~2s timeout = ~28-34 seconds


# Suspected Root Cause
FreeIPA injects KnownHostsCommand during client enrollment which overrides the
local known_hosts file. SSH now asks FreeIPA for host keys on every connection
instead of checking the local file. When FreeIPA is down each lookup times out.
Ansible makes 7-8 SSH connections per module — 14-16 timeouts accumulate to
28-34 seconds. raw module is fast because it uses a single SSH connection.


# More Checks Notes:
Confirmed the KnownHostsCommand source:

Command:
  cat /etc/ssh/ssh_config.d/04-ipa.conf

Output:
  Match exec "true"
      KnownHostsCommand /usr/bin/sss_ssh_knownhosts %H

FreeIPA injects this during client enrollment. Overrides local known_hosts lookup.


# Suspected Solution
Disable KnownHostsCommand specifically for Ansible connections via
ansible_ssh_common_args. Targeted fix — does not affect system-wide SSH behavior.


# Test
Added to inventory [all:vars]:
  ansible_ssh_common_args='-o KnownHostsCommand=none'

Command:
  time ansible 10.0.64.10 -m ping

Result: PASS
  real 0m2.996s — from 34 seconds down to 3 seconds.

_____________________________________________________________________

[Final Root Cause]
FreeIPA injects KnownHostsCommand into /etc/ssh/ssh_config.d/04-ipa.conf during
client enrollment. This overrides the local known_hosts file — SSH stops checking
manually accepted fingerprints and always queries sss_ssh_knownhosts instead.
When FreeIPA is down, each lookup times out (~2s). Ansible makes 7-8 SSH connections
per module and each triggers 2 SSSD lookups — 14-16 timeouts accumulate to 28-34
seconds total.

_____________________________________________________________________

[Final Solution]
Added KnownHostsCommand=none to ansible_ssh_common_args in inventory.
SSH falls back to local known_hosts — host keys still verified via manually
accepted fingerprints, just not dynamically fetched from FreeIPA.

  ansible/dev/inventory/first_setup_inventory.ini:
    [all:vars]
    ansible_ssh_common_args='-o KnownHostsCommand=none'

Consider adding this to all inventory files as a resilience measure.

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Host keys still verified via local known_hosts. Only change is keys are
no longer dynamically fetched from FreeIPA during Ansible runs.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Alternatives considered and rejected:
  Option A: Reduce SSSD dns_resolver_timeout
    Risk: May cause false failures during network blips, affects user auth

  Option B: Modify /etc/ssh/ssh_config.d/04-ipa.conf directly
    Risk: Affects all SSH connections system-wide, not just Ansible

  Option C: ssh_known_hosts_timeout in sssd.conf [ssh] section
    Risk: May affect other SSH operations unintentionally

  Selected: ansible_ssh_common_args — targeted, Ansible-only, no side effects

Workaround if fix is not applied:
  Use raw module for critical operations when IPA is down — single SSH connection,
  no Python, no cumulative delay.
  ansible all -m raw -a 'systemctl status sshd'

Related files:
  /etc/ssh/ssh_config.d/04-ipa.conf
  /usr/bin/sss_ssh_knownhosts
  ansible/dev/inventory/first_setup_inventory.ini
  disaster-recovery/tmp-ipa-domain-down-part1.md