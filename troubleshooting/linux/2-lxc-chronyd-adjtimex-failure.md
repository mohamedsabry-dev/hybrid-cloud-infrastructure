# TS-LNX-002 | 2026-03-15 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Linux
Sub-techs: LXC, Chronyd, adjtimex, CAP_SYS_TIME, Ansible, Proxmox
Environment: DEV lab.local | all unprivileged LXC containers
Re-opened: No

_____________________________________________________________________

[Issue Description]
Ansible playbook fails when trying to start chronyd on LXC containers.

  fatal: [ex-nginx.lab.local]: FAILED!
  Unable to start service chronyd: Job for chronyd.service failed because
  the control process exited with error code.

  systemctl status chronyd.service:
  Fatal error: adjtimex(0x8001) failed: Operation not permitted

Related ticket: TS-IDN-008 — FreeIPA client NTP skip (same root cause)

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Checked what adjtimex is and why it is failing.

adjtimex() is a kernel syscall that reads and adjusts kernel time-keeping variables.
Chronyd uses it to adjust the system clock.

Checked container capabilities:

Command:
  cat /proc/self/status | grep Cap

Output:
  CAP_SYS_TIME not present — stripped from unprivileged LXC containers for security.

Unprivileged LXC containers use UID namespace isolation. Granting CAP_SYS_TIME
would allow the container to change the HOST system clock — that is a security
boundary that cannot be crossed. By design, unprivileged containers cannot
adjust time.

Checked where LXC containers get their time:

  Proxmox host owns the kernel and runs chronyd.
  LXC containers share the host kernel and inherit time automatically.
  LXC containers do not need their own chronyd — time is already correct.

The systemd drop-in file visible in the error (zzz-lxc-service.conf) is LXC's
systemd integration that modifies service behavior inside containers — it is
expected, not a problem.


# Suspected Root Cause
Unprivileged LXC containers cannot run chronyd. The adjtimex() syscall requires
CAP_SYS_TIME which is stripped for security. LXC containers share the host kernel
and inherit time from the Proxmox host — they should not run their own NTP service.


# More Checks Notes:
Confirmed time is already correct on LXC without chronyd:

Command:
  timedatectl  (on LXC container)

Output:
  System clock synchronized: yes
  NTP service: inactive

Time inherited from host, no NTP needed inside the container.


# Suspected Solution
Skip chronyd on LXC containers in Ansible playbook using ansible_virtualization_type
condition. Ensure Proxmox host runs chrony for all containers to inherit from.


# Test
Added when: ansible_virtualization_type != "lxc" condition to chronyd task,
re-ran playbook against all LXC containers.

Result: PASS — no chronyd errors, time correct on all LXC containers.

_____________________________________________________________________

[Final Root Cause]
Unprivileged LXC containers cannot adjust the system clock. adjtimex() requires
CAP_SYS_TIME which is stripped from unprivileged containers by design — granting
it would let the container modify the host clock. LXC containers share the host
kernel and inherit time automatically from the Proxmox host. Running chronyd
inside an LXC container is both unnecessary and impossible.

_____________________________________________________________________

[Final Solution]
Two changes — skip chronyd on LXC in Ansible, confirm chrony running on Proxmox host.

Proxmox host (pve-dev):
  apt update && apt install chrony -y
  systemctl enable --now chrony
  chronyc tracking  # verify sync

Ansible playbook update (ansible/dev/playbooks/common/ntp.yml):
  - name: Enable and start chronyd
    ansible.builtin.service:
      name: chronyd
      state: started
      enabled: yes
    when: ansible_virtualization_type != "lxc"

  - name: Reminder for LXC host configuration
    ansible.builtin.debug:
      msg: "LXC containers inherit time from host. Ensure chrony runs on Proxmox host."
    when: ansible_virtualization_type == "lxc"
    run_once: true

Detection reference:
  ansible_virtualization_type == "lxc"  → LXC container
  ansible_virtualization_type == "kvm"  → VM

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: If Proxmox host time drifts, all LXC containers drift with it.
Ensure chrony is monitored on the Proxmox host.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Related: TS-IDN-008 — FreeIPA client enrollment also needed NTP skipped on LXC,
same root cause, handled via ipaclient_no_ntp: true.