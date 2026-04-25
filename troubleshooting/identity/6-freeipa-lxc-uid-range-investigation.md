# TS-IDN-006 | 2026-03-05 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Identity / FreeIPA
Sub-techs: FreeIPA UID range, LXC UID namespace mapping, Proxmox, SSSD, SSH
Environment: DEV lab.local | FreeIPA server freeipa.lab.local | all unprivileged LXC containers
Re-opened: No

_____________________________________________________________________

[Issue Description]
Two related failures both rooted in the same UID range problem — discovered in sequence.

Phase 1 — FreeIPA installation fails with UID range validation error:
  fatal: "ipaserver_idstart must be larger than UID_MAX"

Phase 2 — After installing FreeIPA with default UID range, SSH to LXC containers fails:
  ssh super_bot@vault1.lab.local
  Connection to vault1.lab.local closed by remote host.

  SSHD logs on vault1:
  fatal: initgroups: super_bot: Invalid argument

Related ticket: TS-IDN-001 — LXC Kerberos keyring failure (different symptom, same LXC UID root)

_____________________________________________________________________

[Analysis]

# Initial Check Notes:

--- Phase 1: FreeIPA installation UID error ---

Checked what UID_MAX is on the FreeIPA server and why FreeIPA cares about it.

Command:
  grep UID_MAX /etc/login.defs

Output:
  UID_MAX    60000

Linux reserves UIDs 0-60000 for local users created with useradd.
FreeIPA must assign UIDs above this to avoid conflicts between local and domain users.

Checked LXC UID namespace mapping on Proxmox host:

Command:
  cat /etc/subuid

Output:
  root:100000:65536

LXC unprivileged containers map 65536 UIDs (0-65535) from container space to host space.
FreeIPA UIDs must fit within this range to work inside LXC containers.

Safe range calculation:
  UID_MAX (local users)   = 60000  → FreeIPA must be above this
  LXC max supported UID   = 65535  → FreeIPA must be below this
  Safe FreeIPA range      = 60001 - 65535


--- Phase 2: SSH initgroups failure on LXC ---

After FreeIPA was initially installed with default UID range, checked what UID
was assigned to domain users.

Command:
  ipa user-show super_bot --all | grep uidnumber

Output:
  uidnumber: 1719400001

FreeIPA default range assigned UID 1719400001.
LXC unprivileged container can only handle UIDs 0-65535.
UID 1719400001 is completely outside the mapped range.

When SSHD calls initgroups() to set up user groups after auth, the kernel looks
up the UID in the namespace mapping, finds nothing, and returns "Invalid argument."
Auth fails before the session even starts.


# Suspected Root Cause
FreeIPA default UID range (1719400000+) is outside the LXC unprivileged container
mapped UID range (0-65535). And even a correctly chosen range must satisfy both
constraints — above UID_MAX (60000) to avoid local user conflicts, and below 65536
to fit inside the LXC namespace mapping.


# More Checks Notes:
Checked what happens with the unmapped UID at kernel level and confirmed the
mapping boundary.

  Container UID 0     → Host UID 100000   (mapped, works)
  Container UID 65535 → Host UID 165535   (mapped, works)
  Container UID 1719400001                (not mapped, kernel rejects)

Also tried several approaches to work around the UID mapping instead of fixing
the range — all failed:

  1. Manual unprivileged → privileged conversion (edit /etc/pve/lxc/<id>.conf)
     Result: container became inaccessible, permissions broke

  2. Custom UID mapping on Proxmox (extend subuid/subgid with idmap rules)
     Result: complex, error-prone, manual per container

  3. Privileged containers via Terraform
     Result: Permission check failed — API tokens cannot create privileged
     containers with feature flags

  4. Privileged containers without nesting
     Result: Terraform treats systemd warnings as errors, corrupts state

All workaround paths failed. Fixing the UID range at FreeIPA level is the only
clean solution.


# Suspected Solution
Configure FreeIPA UID range within the safe intersection (60001-65500) at
installation time. Recreate domain users so they get UIDs in the correct range.


# Test
Reinstalled FreeIPA with ipaserver_idstart=60001, ipaserver_idmax=65500.
Recreated users and tested SSH to LXC.

Command:
  ipa idrange-show LAB.LOCAL_id_range
  id super_bot
  ssh super_bot@vault1.lab.local

Result: PASS
  Range: First Posix ID 60001, 5500 IDs in range
  id: uid=60001(super_bot) gid=60001(super_bot)
  SSH: [super_bot@vault1 ~]$

_____________________________________________________________________

[Final Root Cause]
FreeIPA default UID range (1719400000+) is outside the LXC unprivileged container
UID namespace mapping (0-65535). When SSHD calls initgroups() after auth, the kernel
rejects the unmapped UID with "Invalid argument." The FreeIPA UID range must satisfy
two constraints simultaneously — above UID_MAX (60000) to avoid local user conflicts,
and below 65536 to fit inside the LXC namespace. The intersection is 60001-65535.

_____________________________________________________________________

[Final Solution]
Configured FreeIPA UID range within safe bounds at installation time.

  ansible/dev/playbooks/freeipa/freeipa_setup.yml:
    ipaserver_idstart: 60001
    ipaserver_idmax: 65500

IMPORTANT: UID range must be set during FreeIPA installation. Changing it after
users exist requires recreating all users.

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Range 60001-65500 supports ~5500 domain users. Sufficient for small/medium
lab deployments. For larger deployments without LXC the upper limit can be raised.

_____________________________________________________________________

[References]
- https://pve.proxmox.com/wiki/Unprivileged_LXC_containers
- https://forum.proxmox.com/threads/understanding-lxc-uid-mappings.101855/

_____________________________________________________________________

[Draft Notes]

UID range planning:
  0     - 999    system users (root, bin, daemon)
  1000  - 60000  local users (useradd)
  60001 - 65500  FreeIPA domain users
  65501 - 65535  reserved buffer

For larger deployments without LXC containers:
  ipaserver_idstart: 60001
  ipaserver_idmax: 200000   (no LXC = no 65536 limit)