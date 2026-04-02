# Case 1: LXC Kerberos Keyring Authentication Failure

**Date:** 2026-03-05
**Environment:** DEV (lab.local)
**Affected Systems:** All LXC containers (vault_cluster, ansible, local_runners, nginx)
**Status:** RESOLVED

---

## Symptom

SSH password authentication fails for FreeIPA domain users on LXC containers, but works on VMs.

### Observed Behavior

```bash
# Admin user on LXC - FAILS (password prompt loops)
[root@ansible dev]# ssh vault_admin@vault1
(vault_admin@vault1) Password:
(vault_admin@vault1) Password:
(vault_admin@vault1) Password:

# Same admin user on VM - WORKS
[root@ansible dev]# ssh k8s_admin@k8s-master1
(k8s_admin@k8s-master1) Password:
[k8s_admin@k8s-master1 ~]$

# Bot user on LXC - WORKS (no password prompt)
[root@ansible dev]# ssh super_bot@vault1
Last login: Thu Mar  5 15:31:55 2026 from 10.0.63.10
[super_bot@vault1 ~]$
```

---

## Investigation

### Step 1: Check SSHD Logs on Affected LXC

```bash
[root@vault1 ~]# journalctl -u sshd -f
```

**Result:**
```
Mar 05 19:23:57 vault1.lab.local sshd-session[11722]: pam_sss(sshd:auth): authentication failure; logname= uid=0 euid=0 tty=ssh ruser= rhost=10.0.63.10 user=vault_admin
Mar 05 19:23:57 vault1.lab.local sshd-session[11722]: pam_sss(sshd:auth): received for user vault_admin: 4 (System error)
Mar 05 19:23:59 vault1.lab.local sshd-session[11719]: error: PAM: Authentication failure for vault_admin from 10.0.63.10
```

**Finding:** PAM returns error code 4 (System error), not authentication denied.

### Step 2: Check SSSD Logs

```bash
[root@vault1 ~]# journalctl -u sssd -f
```

**Result:**
```
Mar 05 19:23:57 vault1.lab.local krb5_child[11724]: Invalid UID in persistent keyring name
Mar 05 19:24:55 vault1.lab.local krb5_child[11739]: Invalid UID in persistent keyring name
```

**Finding:** Kerberos credential storage failing due to keyring UID issue.

### Step 3: Analyze Why super_bot Works

Initial hypothesis: super_bot might use SSH key authentication.

**Test:**
```bash
[root@ansible dev]# ssh super_bot@vault1
Last login: Thu Mar  5 15:31:55 2026 from 10.0.63.10
```

**SSSD log during super_bot login:**
```
Mar 05 19:26:58 vault1.lab.local sssd_be[7291]: GSSAPI client step 1
Mar 05 19:26:58 vault1.lab.local sssd_be[7291]: GSSAPI client step 2
```

**Finding:** super_bot uses GSSAPI (Kerberos ticket), not password authentication.

### Step 4: Verify Kerberos Ticket Exists

```bash
[root@ansible dev]# klist
```

**Result:** Active ticket for super_bot@LAB.LOCAL exists (from previous `kinit super_bot`).

### Step 5: Confirm Theory with Admin User

```bash
[root@ansible dev]# kinit vault_admin
Password for vault_admin@LAB.LOCAL:

[root@ansible dev]# ssh vault_admin@vault1
Last failed login: Thu Mar  5 19:32:20 UTC 2026 on pts/4
There were 7 failed login attempts since the last successful login.
[vault_admin@vault1 ~]$
```

**Result:** After obtaining Kerberos ticket via kinit, SSH works via GSSAPI.

**Confirmed:** Password authentication triggers keyring storage, which fails on LXC.

---

## Root Cause

### Technical Explanation

1. **Kerberos Credential Cache:** By default, SSSD uses the kernel keyring (`KEYRING:persistent:%{uid}`) to store Kerberos tickets after password authentication.

2. **LXC UID Namespace Mapping:** Unprivileged LXC containers map container UIDs to different host UIDs for security isolation:
   - Container sees: UID 60001 (vault_admin)
   - Host kernel sees: UID 160001+ (mapped range)

3. **Keyring Validation Failure:** When `krb5_child` requests a keyring with the container's UID, the kernel rejects it because the actual UID (from host perspective) doesn't match the requested keyring name.

4. **Result:** `Invalid UID in persistent keyring name` → authentication fails with system error.

### Why VMs Are Unaffected

VMs run their own kernel with no UID namespace mapping. The UID seen by the process matches the UID used for keyring operations.

### Why GSSAPI Authentication Works

When using pre-obtained Kerberos tickets (`kinit`), the ticket is stored on the **source machine** (ansible node). SSH forwards authentication via GSSAPI protocol - the target LXC never needs to store a new ticket locally.

---

## Solution

### Fix Applied

Changed Kerberos credential cache from kernel keyring to file-based storage in SSSD configuration.

**File:** `/etc/sssd/sssd.conf`

**Change:**
```ini
[domain/lab.local]
krb5_ccache_template = FILE:/tmp/krb5cc_%U
```

### Ansible Playbook

**File:** `playbooks/freeipa/fix_lxc_krb5_keyring.yml`

```yaml
---
- name: Fix Kerberos keyring issue on LXC containers
  hosts: vault_cluster:ansible:local_runners:nginx
  become: yes

  tasks:
    - name: Add FILE-based krb5 ccache to sssd.conf
      ansible.builtin.lineinfile:
        path: /etc/sssd/sssd.conf
        regexp: '^krb5_ccache_template'
        line: 'krb5_ccache_template = FILE:/tmp/krb5cc_%U'
        insertafter: '^\[domain/'
        state: present
      notify:
        - Clear SSSD cache
        - Restart SSSD

  handlers:
    - name: Clear SSSD cache
      ansible.builtin.command:
        cmd: sss_cache -E

    - name: Restart SSSD
      ansible.builtin.service:
        name: sssd
        state: restarted
```

### Verification

```bash
# Destroy existing tickets
[root@ansible dev]# kdestroy

# Test password authentication (no kinit)
[root@ansible dev]# ssh vault_admin@vault1
(vault_admin@vault1) Password:
[vault_admin@vault1 ~]$
```

**Result:** Password authentication now works on LXC containers.

---

## Affected Components

| Component | Type | Issue | Fixed |
|-----------|------|-------|-------|
| vault1.lab.local | LXC | Keyring failure | Yes |
| vault2.lab.local | LXC | Keyring failure | Yes |
| vault3.lab.local | LXC | Keyring failure | Yes |
| ansible.lab.local | LXC | Keyring failure | Yes |
| local-runner.lab.local | LXC | Keyring failure | Yes |
| ex-nginx.lab.local | LXC | Keyring failure | Yes |
| k8s-master*.lab.local | VM | Not affected | N/A |
| k8s-worker*.lab.local | VM | Not affected | N/A |

---

## Lessons Learned

1. **LXC containers have kernel-level differences** from VMs that affect system services relying on kernel features (keyrings, cgroups, etc.).

2. **"System error" from PAM** indicates infrastructure issues, not authentication/authorization failures.

3. **GSSAPI vs Password auth** take different code paths - one can work while the other fails.

4. **Systematic testing** (comparing working vs non-working scenarios) quickly narrows down the variable causing the issue.

---

## References

- [SSSD and Kerberos Credential Caches](https://sssd.io/docs/users/krb5_ccache.html)
- [LXC Unprivileged Containers](https://linuxcontainers.org/lxc/security/)
- [Kernel Keyring Subsystem](https://www.kernel.org/doc/html/latest/security/keys/core.html)

---

## Timeline

| Time | Action |
|------|--------|
| 19:23 | Issue reported - vault_admin SSH fails on vault1 |
| 19:24 | Checked SSHD logs - found PAM system error |
| 19:25 | Checked SSSD logs - found keyring UID error |
| 19:26 | Analyzed super_bot success - discovered GSSAPI usage |
| 19:29 | Confirmed kinit + SSH works for vault_admin |
| 19:32 | Applied fix - FILE-based ccache |
| 19:35 | Verified fix - password auth works |
