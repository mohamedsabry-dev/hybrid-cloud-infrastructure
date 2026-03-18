# TS-024: LXC Chronyd adjtimex Failure

**Date:** 2026-03-15
**Environment:** DEV (lab.local)
**Affected Systems:** All unprivileged LXC containers
**Status:** RESOLVED

---

## Symptom

Ansible playbook fails when starting chronyd on LXC containers:

```
fatal: [ex-nginx.lab.local]: FAILED! => {
    "changed": false,
    "msg": "Unable to start service chronyd: Job for chronyd.service failed because the control process exited with error code."
}
```

Service status shows:

```bash
systemctl status chronyd.service
```

```
× chronyd.service - NTP client/server
     Active: failed (Result: exit-code)
    Drop-In: /run/systemd/system/service.d
             └─zzz-lxc-service.conf

Fatal error : adjtimex(0x8001) failed : Operation not permitted
```

---

## Root Cause

**Unprivileged LXC containers cannot adjust the system clock.**

The `adjtimex()` syscall requires `CAP_SYS_TIME` capability, which is stripped from unprivileged containers for security. LXC containers share the host kernel and inherit time from the Proxmox host - they cannot run their own time sync.

```
Proxmox Host (runs chronyd)
    │
    └── LXC Containers (inherit time, cannot run chronyd)
```

---

## Solution

### Step 1: Configure Chrony on Proxmox Host

```bash
# Install chrony
apt update && apt install chrony -y

# Enable and start
systemctl enable chrony
systemctl start chrony

# Verify
systemctl status chrony
chronyc tracking
```

### Step 2: Update Ansible Playbook - Skip chronyd on LXC

```yaml
- name: Enable and start chronyd
  ansible.builtin.service:
    name: chronyd
    state: started
    enabled: yes
  when: ansible_virtualization_type != "lxc"
```

### Step 3: Set Timezone on Containers

```yaml
- name: Set timezone
  community.general.timezone:
    name: Africa/Cairo
```

### Step 4: Add Reminder for Host Configuration

```yaml
- name: Reminder for LXC host configuration
  ansible.builtin.debug:
    msg:
      - "NOTE: LXC containers inherit time from the host."
      - "Ensure chrony is installed and running on the Proxmox host."
      - "Run on host: apt install chrony && systemctl enable --now chrony"
  when: ansible_virtualization_type == "lxc"
  run_once: true
```

---

## Verification

**Proxmox host:**
```bash
chronyc tracking
# Stratum should be > 0
```

**LXC container:**
```bash
timedatectl
# System clock synchronized: yes
# NTP service: inactive (expected)
```

---

## Related Cases

- [TS-018: LXC NTP Configuration Disabled](18-lxc-ntp-configuration-disabled.md)
