# TS-IDN-002 | 2026-03-05 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Identity / FreeIPA
Sub-techs: BIND DNS, FreeIPA DNS, DNS forwarders, recursion, Ansible
Environment: DEV lab.local | FreeIPA server freeipa.lab.local | all domain clients
Re-opened: No

_____________________________________________________________________

[Issue Description]
FreeIPA domain clients cannot resolve external domains. FreeIPA server itself resolves fine.

  # From client (vault1.lab.local) — FAILS
  dig @10.0.60.10 google.com
  status: REFUSED
  WARNING: recursion requested but not available
  EDE: 18 (Prohibited)

  # From FreeIPA server itself — WORKS
  dig google.com
  → valid response

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
First checked if forwarders were even configured in FreeIPA — the playbook has
ipaserver_forwarders set in vars so expected them to be applied.

Command:
  ipa dnsconfig-show

Output:
  Empty — no forwarders configured at all. The ipaserver_forwarders var in the
  role did not apply. This was the first problem.

Then figured out why server resolves fine but clients get REFUSED.
BIND defaults to allowing recursion only from localhost (127.0.0.1).
When a client at 10.0.x.x asks FreeIPA DNS to resolve google.com:
  1. FreeIPA DNS doesn't know google.com directly
  2. It needs to ask upstream DNS — this is recursion
  3. BIND only allows recursion from 127.0.0.1
  4. Client request gets REFUSED

From the server itself, dig works because it queries from 127.0.0.1 — localhost is allowed.
This was the second problem.


# Suspected Root Cause
Two problems combined:
  1. Forwarders not applied — ipaserver_forwarders var in the role didn't work
  2. Recursion denied — BIND default only allows recursion from 127.0.0.1, not from
     internal network clients


# More Checks Notes:
Confirmed BIND recursion restriction by checking named config.

Command:
  cat /etc/named/ipa-options-ext.conf

Output:
  File exists but no allow-recursion or allow-query-cache directives present.
  BIND falling back to default — localhost only.


# Suspected Solution
Add post_tasks to the FreeIPA setup playbook to handle both problems:
  1. Configure forwarders (8.8.8.8, 1.1.1.1) via ipadnsconfig module
  2. Add allow-recursion and allow-query-cache for 10.0.0.0/8 in ipa-options-ext.conf


# Test
Applied post_tasks to freeipa_setup.yml and ran the playbook.

Command:
  ipa dnsconfig-show
  dig @10.0.60.10 google.com  (from client vault1)

Result: PASS — forwarders confirmed applied, external resolution working from all clients.

_____________________________________________________________________

[Final Root Cause]
Two problems combined. Forwarders were never applied — the ipaserver_forwarders var
in the FreeIPA Ansible role did not configure DNS forwarders on the server. Even if
forwarders had been set, BIND denies recursive queries from non-localhost by default.
Clients at 10.0.x.x asking FreeIPA DNS to resolve external domains got REFUSED because
BIND would not perform recursive lookups on their behalf. The server itself worked
because it queries from 127.0.0.1 which BIND allows by default.

_____________________________________________________________________

[Final Solution]
Two fixes added as post_tasks in ansible/dev/playbooks/freeipa/freeipa_setup.yml:

1. Configure DNS forwarders via ipadnsconfig module:
     forwarders: 8.8.8.8, 1.1.1.1
     forward_policy: first
     allow_sync_ptr: yes

2. Allow recursion from internal network in /etc/named/ipa-options-ext.conf:
     allow-recursion { 127.0.0.1; 10.0.0.0/8; };
     allow-query-cache { 127.0.0.1; 10.0.0.0/8; };

Named restarted via handler after config change.

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Opening recursion to 10.0.0.0/8 is acceptable for internal lab network.
Would be a risk if FreeIPA DNS were exposed to the internet.

_____________________________________________________________________

[References]


_____________________________________________________________________

[Draft Notes]

IMPORTANT — wrong config file will break things:
  Use: /etc/named/ipa-options-ext.conf  (included INSIDE BIND options block — correct)
  NOT: /etc/named/ipa-ext.conf          (outside the options context — wrong)

Forwarders syntax gotcha in ansible-freeipa module:
  # WRONG — plain strings cause "dictionary requested" error
  forwarders:
    - 8.8.8.8

  # CORRECT — must use ip_address key
  forwarders:
    - ip_address: 8.8.8.8
    - ip_address: 1.1.1.1

  Module expects dicts because it supports optional port field:
    - ip_address: 8.8.8.8
      port: 53

Workaround (manual, without Ansible):
  ipa dnsconfig-mod --forwarder=8.8.8.8 --forwarder=1.1.1.1
  vi /etc/named/ipa-options-ext.conf
    → add: allow-recursion { 127.0.0.1; 10.0.0.0/8; };
  systemctl restart named