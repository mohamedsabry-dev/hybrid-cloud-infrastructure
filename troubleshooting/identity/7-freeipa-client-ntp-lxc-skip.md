# TS-IDN-008 | 2026-03-05 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Identity / FreeIPA
Sub-techs: FreeIPA client enrollment, Chronyd, NTP, LXC kernel sharing, Ansible
Environment: DEV lab.local | all LXC containers
Re-opened: No

_____________________________________________________________________

[Issue Description]
NTP/Chronyd configuration fails or behaves inconsistently on LXC containers
during FreeIPA domain join. Chronyd fails to start, time sync errors, Ansible
enrollment tasks fail.

Related ticket: TS-LNX-002 — Chronyd adjtimex failure (same root cause, OS-level symptom)

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Investigated how time sync works differently between VMs and LXC containers.

  VMs  → run their own kernel, chronyd works normally
  LXC  → share Proxmox host kernel, inherit time directly from host

LXC containers share the host kernel including the system clock.
They have no independent clock to sync.

Checked what happens when FreeIPA client enrollment tries to configure NTP on LXC:

Command:
  systemctl start chronyd  (during FreeIPA enrollment on LXC)

Output:
  various failures — chronyd requires CAP_SYS_TIME capability which is not
  available in unprivileged LXC containers.

Checked Proxmox host chrony config:

Command:
  cat /etc/chrony/chrony.conf

Output:
  pool 0.pool.ntp.org iburst
  pool 1.pool.ntp.org iburst
  server time.cloudflare.com iburst

Host is syncing correctly. LXC containers inherit this time automatically.


# Suspected Root Cause
LXC containers share the host kernel including the system clock. They cannot run
their own time sync services — chronyd requires CAP_SYS_TIME which unprivileged
containers do not have. FreeIPA client enrollment tries to configure NTP by default,
which fails on LXC. Time sync must happen at the Proxmox host level only.


# More Checks Notes:
Confirmed time is correct on LXC containers without any NTP config.

Command:
  timedatectl  (on LXC container)

Output:
  System clock synchronized: yes
  NTP service: inactive

Time is already correct inherited from host. No NTP needed inside the container.


# Suspected Solution
Disable NTP configuration during FreeIPA client enrollment for LXC containers.
Set ipaclient_no_ntp: true in group_vars.


# Test
Set ipaclient_no_ntp: true in ansible/dev/inventory/group_vars/all.yml and
re-ran FreeIPA client enrollment playbook on LXC containers.

Result: PASS — enrollment completes without NTP errors, time correct on all LXC containers.

_____________________________________________________________________

[Final Root Cause]
LXC unprivileged containers share the Proxmox host kernel and system clock.
They cannot run chronyd because it requires CAP_SYS_TIME capability which
unprivileged containers do not have. FreeIPA client enrollment tries to configure
NTP by default — this fails on LXC. The fix is to skip NTP during enrollment since
LXC containers already have correct time inherited from the host.

_____________________________________________________________________

[Final Solution]
Disabled NTP configuration during FreeIPA client enrollment via Ansible group_vars.

  ansible/dev/inventory/group_vars/all.yml:
    ipaclient_no_ntp: true          # this is the one that actually skips NTP
    ipaclient_configure_ntp: false  # set for completeness
    # ipaclient_ntp_servers:        # must be commented out, not just false

IMPORTANT: The correct variable is ipaclient_no_ntp: true — not ipaclient_configure_ntp: false.
The role checks for no_ntp to skip the NTP setup step entirely.

NTP architecture going forward:
  Proxmox host   → syncs from external NTP (pool.ntp.org, time.cloudflare.com)
  FreeIPA server → syncs from external NTP + serves as NTP for domain (allow 10.0.0.0/16)
  LXC containers → skip NTP config, inherit time from Proxmox host automatically
  VMs            → can use FreeIPA as NTP source

Both Proxmox and FreeIPA use the same external sources — consistent time across
the whole environment.

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: If Proxmox host time drifts, all LXC containers drift with it. Ensure
chrony is properly configured and monitored on the Proxmox host.

_____________________________________________________________________

[References]


_____________________________________________________________________

[Draft Notes]

Commands for time verification:
  timedatectl                          check time status on any host
  timedatectl set-timezone Africa/Cairo  set timezone on container
  systemctl status chrony              check NTP on Proxmox host
  chronyc tracking                     check sync status
  chronyc sources -v                   check NTP sources