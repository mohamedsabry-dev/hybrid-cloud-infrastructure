# TS-IDN-001 | 2026-03-05 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Identity / FreeIPA
Sub-techs: SSSD, Kerberos, PAM, GSSAPI, LXC UID mapping, Ansible
Environment: DEV lab.local | LXC containers: vault_cluster, ansible, local_runners, nginx
Re-opened: No

_____________________________________________________________________

[Issue Description]
SSH password auth fails for FreeIPA domain users on LXC containers. 
Same users work fine on VMs. Bot user (super_bot) could SSH into LXC with no issue.

  # FAILS on LXC — password prompt loops
  ssh vault_admin@vault1
  (vault_admin@vault1) Password:
  (vault_admin@vault1) Password:
  (vault_admin@vault1) Password:

  # WORKS on VM
  ssh k8s_admin@k8s-master1
  [k8s_admin@k8s-master1 ~]$

  # WORKS on LXC — bot user no password prompt
  ssh super_bot@vault1
  [super_bot@vault1 ~]$

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
The bot user working was the first clue. Started from there.

Checked SSHD logs on affected LXC (vault1):

Command:
  journalctl -u sshd -f

Output:
  pam_sss(sshd:auth): authentication failure; user=vault_admin
  pam_sss(sshd:auth): received for user vault_admin: 4 (System error)
  error: PAM: Authentication failure for vault_admin from 10.0.63.10

PAM returned error code 4 — System error. Not wrong password, not access denied.
Something broke at infrastructure level before it even got to checking credentials.

Checked SSSD logs:

Command:
  journalctl -u sssd -f

Output:
  krb5_child[11724]: Invalid UID in persistent keyring name
  krb5_child[11739]: Invalid UID in persistent keyring name

Kernel keyring is where SSSD tries to store the Kerberos ticket after password auth.
This is failing before auth completes.

Checked why super_bot works:

Command:
  journalctl -u sssd -f  (during super_bot login)

Output:
  sssd_be[7291]: GSSAPI client step 1
  sssd_be[7291]: GSSAPI client step 2

super_bot is not using password auth at all. It already had a Kerberos ticket from a
previous kinit on the ansible node — SSH forwarded the auth via GSSAPI. The target LXC
never had to store a ticket locally, so the keyring issue never triggered.

Command:
  klist

Output:
  Active ticket for super_bot@LAB.LOCAL exists.

Password auth and GSSAPI take completely different code paths. That explained the inconsistency.


# Suspected Root Cause
LXC containers remap UIDs — a user with UID 60001 inside the container is actually
UID 160001+ on the host. When krb5_child asks the kernel to create a keyring for
UID 60001, the kernel checks the actual UID, sees they don't match, and rejects it.
VMs run their own kernel with no UID remapping so they are not affected.


# More Checks Notes:
Confirmed theory by manually getting a Kerberos ticket for vault_admin then trying SSH.

Command:
  kinit vault_admin
  ssh vault_admin@vault1

Output:
  [vault_admin@vault1 ~]$
  (SSH worked — via GSSAPI, same as super_bot)

Confirmed: password auth triggers keyring storage on target LXC, which fails.
GSSAPI auth stores the ticket on the source machine only, never touches target keyring.


# Suspected Solution
Switch Kerberos credential cache from kernel keyring to file-based storage on all LXC containers.
File storage writes to /tmp — does not care about UID mapping.


# Test
Added krb5_ccache_template = FILE:/tmp/krb5cc_%U to sssd.conf on vault1.
Destroyed existing tickets and tested password auth with no kinit.

Command:
  kdestroy
  ssh vault_admin@vault1

Result: PASS — password auth works on LXC without needing kinit first.

_____________________________________________________________________

[Final Root Cause]
SSSD uses kernel keyring (KEYRING:persistent:%{uid}) to store Kerberos tickets after
password auth. LXC unprivileged containers map UIDs — container UID 60001 maps to host
UID 160001+. When krb5_child requests a keyring with the container UID, the kernel
rejects it because the actual UID does not match. Auth fails with system error before
credentials are even checked.

VMs are not affected — they run their own kernel with no UID namespace mapping.
GSSAPI is not affected — ticket is stored on the source machine, target LXC never
stores anything locally.

_____________________________________________________________________

[Final Solution]
One line added under [domain/lab.local] in /etc/sssd/sssd.conf on every LXC container:

  krb5_ccache_template = FILE:/tmp/krb5cc_%U

This tells SSSD to store Kerberos tickets as a file in /tmp instead of the kernel keyring.
Files do not care about UID mapping — problem solved.

Deployed via Ansible to all LXC containers:
  Playbook: ansible/dev/playbooks/freeipa/fix_lxc_krb5_keyring.yml
  Hosts: vault_cluster, ansible, local_runners, nginx

Playbook does: check sssd.conf exists → backup → add line → clear SSSD cache → restart SSSD.

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: File-based cache in /tmp is slightly less secure than kernel keyring.
Acceptable for this lab environment.

_____________________________________________________________________

[References]
- https://forum.proxmox.com/threads/understanding-lxc-uid-mappings.101855/
_____________________________________________________________________

[Draft Notes]

Related tickets (same UID mapping root cause):
  - TS-IDN-006 — FreeIPA UID range for LXC compatibility
  - TS-IDN-007 — LXC initgroups error

Impact:
  vault1/2/3.lab.local         LXC  Fixed
  ansible.lab.local            LXC  Fixed
  local-runner.lab.local       LXC  Fixed
  ex-nginx.lab.local           LXC  Fixed
  k8s-master*.lab.local        VM   Not affected
  k8s-worker*.lab.local        VM   Not affected


Key lessons:
  - PAM "System error" = infrastructure failure, not auth/authz issue — check SSSD logs next
  - LXC has kernel-level differences from VMs: keyrings, cgroups, UID namespaces
  - GSSAPI and password auth take completely different code paths