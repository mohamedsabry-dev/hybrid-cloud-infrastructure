# TS-IDN-001 | 2026-03-05 | RESOLVED

## 1. Context
- System: FreeIPA / SSSD / Kerberos
- Environment: DEV (lab.local)
- Related components: All LXC containers (vault_cluster, ansible, local_runners, nginx)
- **Related tickets:**
  - [TS-IDN-006](6-freeipa-uid-range-lxc-compatibility.md) - FreeIPA UID range for LXC (same UID mapping root cause)
  - [TS-IDN-007](7-lxc-uid-mapping-initgroups-error.md) - LXC initgroups error (same UID mapping root cause)

## 2. Issue
- Symptom: SSH password auth fails for FreeIPA domain users on LXC containers, works on VMs
- Error:
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

## 3. Analysis

**Check 1: SSHD logs on affected LXC**
```bash
[root@vault1 ~]# journalctl -u sshd -f
```
```
Mar 05 19:23:57 vault1.lab.local sshd-session[11722]: pam_sss(sshd:auth): authentication failure; logname= uid=0 euid=0 tty=ssh ruser= rhost=10.0.63.10 user=vault_admin
Mar 05 19:23:57 vault1.lab.local sshd-session[11722]: pam_sss(sshd:auth): received for user vault_admin: 4 (System error)
Mar 05 19:23:59 vault1.lab.local sshd-session[11719]: error: PAM: Authentication failure for vault_admin from 10.0.63.10
```
Finding: PAM returns error code 4 (System error), not authentication denied.

**Check 2: SSSD logs**
```bash
[root@vault1 ~]# journalctl -u sssd -f
```
```
Mar 05 19:23:57 vault1.lab.local krb5_child[11724]: Invalid UID in persistent keyring name
Mar 05 19:24:55 vault1.lab.local krb5_child[11739]: Invalid UID in persistent keyring name
```
Finding: Kerberos credential storage failing due to keyring UID issue.

**Check 3: Why does super_bot work?**
```bash
[root@ansible dev]# ssh super_bot@vault1
Last login: Thu Mar  5 15:31:55 2026 from 10.0.63.10
```
SSSD log during super_bot login:
```
Mar 05 19:26:58 vault1.lab.local sssd_be[7291]: GSSAPI client step 1
Mar 05 19:26:58 vault1.lab.local sssd_be[7291]: GSSAPI client step 2
```
Finding: super_bot uses GSSAPI (Kerberos ticket), not password authentication.

**Check 4: Verify Kerberos ticket exists**
```bash
[root@ansible dev]# klist
```
Result: Active ticket for super_bot@LAB.LOCAL exists (from previous `kinit super_bot`).

**Check 5: Confirm theory with admin user**
```bash
[root@ansible dev]# kinit vault_admin
Password for vault_admin@LAB.LOCAL:

[root@ansible dev]# ssh vault_admin@vault1
Last failed login: Thu Mar  5 19:32:20 UTC 2026 on pts/4
There were 7 failed login attempts since the last successful login.
[vault_admin@vault1 ~]$
```
Result: After obtaining Kerberos ticket via kinit, SSH works via GSSAPI.

Confirmed: Password authentication triggers keyring storage, which fails on LXC.

## 4. Root Cause
> 1. SSSD uses kernel keyring (`KEYRING:persistent:%{uid}`) to store Kerberos tickets after password auth
> 2. LXC unprivileged containers map UIDs (container UID 60001 → host UID 160001+)
> 3. When `krb5_child` requests keyring with container UID, kernel rejects it - actual UID doesn't match
> 4. Result: `Invalid UID in persistent keyring name` → authentication fails with system error

**Why VMs work:** VMs run their own kernel, no UID namespace mapping.

**Why GSSAPI works:** Ticket stored on source machine (ansible node), SSH forwards auth via GSSAPI - target LXC never stores ticket locally.

## 5. Solution
> Change Kerberos credential cache from kernel keyring to file-based storage.

**Why this works:** LXC containers have UID mapping (container UID 60001 → host UID 160001), so kernel keyring rejects requests because UIDs don't match. File storage (`/tmp/krb5cc_UID`) doesn't care about UID mapping - it just writes a file. Problem solved.

**Playbook:** `ansible/dev/playbooks/freeipa/fix_lxc_krb5_keyring.yml`

**Location:** On each LXC container (vault_cluster, ansible, local_runners, nginx)

**Config file edited:** `/etc/sssd/sssd.conf` (on each LXC container)

**Line added under `[domain/lab.local]` section:**
```ini
krb5_ccache_template = FILE:/tmp/krb5cc_%U
```

**Full playbook:**
```yaml
---
- name: Fix Kerberos keyring issue on LXC containers
  hosts: lxc
  become: yes

  tasks:
    - name: Check if sssd.conf exists
      ansible.builtin.stat:
        path: /etc/sssd/sssd.conf
      register: sssd_conf

    - name: Backup sssd.conf
      ansible.builtin.copy:
        src: /etc/sssd/sssd.conf
        dest: /etc/sssd/sssd.conf.backup
        remote_src: yes
        mode: preserve
      when: sssd_conf.stat.exists

    - name: Add FILE-based krb5 ccache to sssd.conf
      ansible.builtin.lineinfile:
        path: /etc/sssd/sssd.conf
        regexp: '^krb5_ccache_template'
        line: 'krb5_ccache_template = FILE:/tmp/krb5cc_%U'
        insertafter: '^\[domain/'
        state: present
      when: sssd_conf.stat.exists
      notify:
        - Clear SSSD cache
        - Restart SSSD

  handlers:
    - name: Clear SSSD cache
      ansible.builtin.command:
        cmd: sss_cache -E
      changed_when: true

    - name: Restart SSSD
      ansible.builtin.service:
        name: sssd
        state: restarted
```

**Verification:**
```bash
# Destroy existing tickets
[root@ansible dev]# kdestroy

# Test password authentication (no kinit)
[root@ansible dev]# ssh vault_admin@vault1
(vault_admin@vault1) Password:
[vault_admin@vault1 ~]$
```
Result: Password authentication now works on LXC containers.

## 6. Solution Risk
- Risk level: LOW
- Potential impact: File-based cache in /tmp slightly less secure than kernel keyring, acceptable for this environment

## 7. Impact After Fix
- Observed: Password auth works on all LXC containers

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

## 8. Notes
- LXC containers have kernel-level differences from VMs (keyrings, cgroups, etc.)
- "System error" from PAM = infrastructure issue, not auth/authz failure
- GSSAPI vs Password auth take different code paths

**Timeline:**
| Time | Action |
|------|--------|
| 19:23 | Issue reported - vault_admin SSH fails on vault1 |
| 19:24 | Checked SSHD logs - found PAM system error |
| 19:25 | Checked SSSD logs - found keyring UID error |
| 19:26 | Analyzed super_bot success - discovered GSSAPI usage |
| 19:29 | Confirmed kinit + SSH works for vault_admin |
| 19:32 | Applied fix - FILE-based ccache |
| 19:35 | Verified fix - password auth works |

## 9. Workaround (if any)
> Use `kinit username` before SSH to get GSSAPI auth (bypasses keyring storage on target).

## References
- [SSSD and Kerberos Credential Caches](https://sssd.io/docs/users/krb5_ccache.html)
- [LXC Unprivileged Containers](https://linuxcontainers.org/lxc/security/)
- [Kernel Keyring Subsystem](https://www.kernel.org/doc/html/latest/security/keys/core.html)
