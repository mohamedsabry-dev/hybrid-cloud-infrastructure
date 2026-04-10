# TS-LNX-002 | 2026-03-15 | RESOLVED

## 1. Context
- System: LXC / Chronyd / Systemd
- Environment: DEV (lab.local)
- Related components: All unprivileged LXC containers
- **Related tickets:** [TS-IDN-008](../identity/8-freeipa-client-ntp-lxc-skip.md) - FreeIPA client NTP skip (same root cause, IPA enrollment config)

## 2. Issue
- Symptom: Ansible playbook fails when starting chronyd on LXC containers
- Error:
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

## 3. Analysis

**Check 1: What is adjtimex?**
```
adjtimex() - system call to read/adjust kernel time-keeping variables
Used by chronyd to adjust system clock
```
Finding: chronyd is trying to adjust the system clock.

**Check 2: Why "Operation not permitted"?**
```bash
# Check container capabilities
cat /proc/self/status | grep Cap
```
Finding: Unprivileged LXC containers don't have `CAP_SYS_TIME` capability - stripped for security.

**Check 3: Can we add the capability?**
```
Unprivileged LXC = UID namespace isolation
CAP_SYS_TIME would allow container to change HOST time
This is a security boundary - cannot be granted
```
Finding: By design, unprivileged containers cannot adjust time.

**Check 4: Where does time come from in LXC?**
```
Proxmox Host (owns the kernel)
    │
    ├── chronyd (adjusts system clock)
    │
    └── LXC Containers (share kernel, inherit time)
```
Finding: LXC containers inherit time from host - they don't need their own chronyd.

## 4. Root Cause
> Unprivileged LXC containers cannot adjust the system clock. The `adjtimex()` syscall requires `CAP_SYS_TIME` capability, which is stripped from unprivileged containers for security. LXC containers share the host kernel and must inherit time from Proxmox host.

## 5. Solution
> Skip chronyd on LXC containers, ensure Proxmox host runs chronyd.

**Why this works:** LXC containers automatically inherit correct time from host. No need for chronyd inside container.

**Step 1: Configure chrony on Proxmox host**

**Location:** On Proxmox host (pve-dev)

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

**Step 2: Update Ansible playbook - skip chronyd on LXC**

**File:** `ansible/dev/playbooks/common/ntp.yml` (or relevant playbook)

**Location:** Ansible playbook configuration

```yaml
- name: Enable and start chronyd
  ansible.builtin.service:
    name: chronyd
    state: started
    enabled: yes
  when: ansible_virtualization_type != "lxc"

- name: Set timezone (works on all systems)
  community.general.timezone:
    name: Africa/Cairo

- name: Reminder for LXC host configuration
  ansible.builtin.debug:
    msg:
      - "NOTE: LXC containers inherit time from the host."
      - "Ensure chrony is installed and running on the Proxmox host."
      - "Run on host: apt install chrony && systemctl enable --now chrony"
  when: ansible_virtualization_type == "lxc"
  run_once: true
```

**Verification:**

On Proxmox host:
```bash
chronyc tracking
# Reference ID    : A29FC801 (time.cloudflare.com)
# Stratum         : 3
# ...
```

On LXC container:
```bash
timedatectl
# System clock synchronized: yes
# NTP service: inactive (expected)
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact: If Proxmox host time drifts, all LXC containers drift. Ensure chrony on host is working.

## 7. Impact After Fix
- Observed: Ansible playbooks run without chronyd errors on LXC
- LXC containers have correct time inherited from host
- No new issues caused

## 8. Notes

**Detection in Ansible:**
```yaml
# ansible_virtualization_type == "lxc" for LXC containers
# ansible_virtualization_type == "kvm" for VMs
```

**LXC drop-in file:**
The error shows `Drop-In: /run/systemd/system/service.d └─zzz-lxc-service.conf` - this is LXC's systemd integration that modifies service behavior in containers.

## 9. Workaround (if any)
> N/A - this IS the correct approach. LXC containers should not run chronyd.

## Related Cases
- [TS-IDN-008: FreeIPA Client NTP Skip](../identity/8-freeipa-client-ntp-lxc-skip.md)
