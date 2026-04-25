# TS-IDN-003 | 2026-03-05 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Identity / FreeIPA
Sub-techs: Kerberos, GSSAPI, SSH, Ansible inventory
Environment: DEV lab.local | all FreeIPA domain hosts | Ansible control node
Re-opened: No

_____________________________________________________________________

[Issue Description]
SSH works with hostnames but fails with IP addresses for FreeIPA domain users.
Same behavior in Ansible — inventory with IPs fails, inventory with FQDNs works.

  # Using IP — FAILS
  ssh super_bot@10.0.64.11
  Permission denied (publickey,gssapi-keyex,gssapi-with-mic,password)

  # Using hostname — WORKS
  ssh super_bot@k8s-worker1.lab.local
  [super_bot@k8s-worker1 ~]$

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Traced how Kerberos authentication works to understand why IP vs hostname matters.

Kerberos flow with hostname:
  1. Client requests ticket for: host/k8s-worker1.lab.local@LAB.LOCAL
  2. KDC checks: does this principal exist? Yes.
  3. Client presents ticket to server
  4. Server validates: am I k8s-worker1.lab.local? Yes.
  5. Authentication succeeds.

Kerberos flow with IP:
  1. Client requests ticket for: host/10.0.64.11@LAB.LOCAL
  2. KDC checks: does this principal exist? No.
  3. Authentication fails immediately.

The service principal is registered as host/FQDN@REALM, not host/IP@REALM.
There is no host/10.0.64.11@LAB.LOCAL principal in the KDC.

Command:
  ssh -v super_bot@10.0.64.11 2>&1 | grep -i gssapi
  ssh -v super_bot@k8s-worker1.lab.local 2>&1 | grep -i gssapi

Output:
  IP:       GSSAPI authentication failed — no matching principal
  Hostname: GSSAPI authentication succeeded


# Suspected Root Cause
Kerberos principals are tied to hostnames, not IPs. When SSH connects via IP,
Kerberos cannot find a matching principal and auth fails before even reaching
password fallback.


# More Checks Notes:
Checked Ansible inventory to confirm IPs were being used as connection targets.

Command:
  cat ansible/dev/inventory/inventory.ini

Output:
  [k8s_workers]
  k8s-worker1.lab.local ansible_host=10.0.64.10
  k8s-worker2.lab.local ansible_host=10.0.64.11
  k8s-worker3.lab.local ansible_host=10.0.64.12

ansible_host overrides the connection target to the IP — Ansible connects to the IP
even though the inventory name is the FQDN. This is why Ansible was also failing.


# Suspected Solution
Remove ansible_host from inventory. Let Ansible resolve the FQDN directly via
FreeIPA DNS. SSH will connect to the hostname and Kerberos will find the principal.


# Test
Removed ansible_host entries, ran ansible ping against all hosts.

Command:
  ansible all -m ping

Result: PASS — all hosts green, GSSAPI auth working across the board.

_____________________________________________________________________

[Final Root Cause]
Kerberos service principals are registered as host/FQDN@REALM format
(e.g. host/k8s-worker1.lab.local@LAB.LOCAL). There is no principal for IP addresses.
When SSH or Ansible connects via IP, Kerberos requests a ticket for host/IP@REALM
which does not exist in the KDC — authentication fails. The Ansible inventory had
ansible_host set to IPs, so even though inventory names were FQDNs, the actual
connection was going to the IP.

_____________________________________________________________________

[Final Solution]
Removed ansible_host from Ansible inventory. FreeIPA DNS resolves hostnames
correctly so explicit IPs are not needed.

  Before:
    k8s-worker1.lab.local ansible_host=10.0.64.10

  After:
    k8s-worker1.lab.local

File: ansible/dev/inventory/inventory.ini
Applied to all host groups.

Prerequisites for this to work:
  - FreeIPA DNS must be working (clients using FreeIPA as DNS server)
  - Kerberos ticket must exist (kinit username before running Ansible or SSH)

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: No impact — using proper hostnames as intended by Kerberos design.
Note: Keep initial inventory in seprate file with ip normally as full back using root key trust if domain down

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

If connecting via IP is unavoidable:
  Option 1: Disable GSSAPI, fall back to password auth
    ssh -o GSSAPIAuthentication=no user@10.0.64.11

  Option 2: Add IP to /etc/hosts on client with the hostname
    10.0.64.11 k8s-worker1.lab.local k8s-worker1
    (SSH resolves IP back to hostname, Kerberos finds the principal)

  Option 3: Use root with SSH key — all nodes have ansible public key injected
    during infra init phase via GitHub workflow, so root SSH bypasses Kerberos entirely.
    ssh root@10.0.64.11