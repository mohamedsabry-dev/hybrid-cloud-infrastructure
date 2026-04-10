# TS-PVE-003 | 2026-03-05 | RESOLVED

## 1. Context
- System: Proxmox VE with cloud-init VMs
- Environment: DEV (lab.local)
- Related components: FreeIPA, SSSD, SSHD, cloud-init
- Affected: All VMs provisioned with cloud-init (k8s_masters, k8s_workers)

## 2. Issue
- Symptom: FreeIPA domain users cannot SSH to VMs despite correct HBAC rules
- Error:
```bash
ssh super_bot@k8s-master1.lab.local
super_bot@k8s-master1.lab.local: Permission denied (publickey,gssapi-keyex,gssapi-with-mic).
```

Note: No `password` option listed in the error - password authentication is disabled.

## 3. Analysis

**Check what authentication methods are offered:**
```bash
ssh -v super_bot@k8s-master1.lab.local 2>&1 | grep "Authentications that can continue"
```

**Finding:** Cloud-init creates a drop-in configuration file that **overrides** the main sshd_config:

```bash
cat /etc/ssh/sshd_config.d/50-cloud-init.conf
# PasswordAuthentication no
```

This file disables password authentication. The error shows only `publickey,gssapi-*` methods - no `password`.

**Why users can't authenticate:**
- SSH keys: Not configured for FreeIPA users
- Password: Disabled by cloud-init
- Kerberos (GSSAPI): Works but requires `kinit` first

**Drop-in Config Priority:**

SSH config files in `/etc/ssh/sshd_config.d/` are processed in alphabetical order. Files that start with lower numbers are loaded first, but **later settings override earlier ones**.

```
/etc/ssh/sshd_config              # Main config (PasswordAuthentication yes)
/etc/ssh/sshd_config.d/50-cloud-init.conf  # Overrides with "no"
```

## 4. Root Cause
> Cloud-init disables password authentication by default via `/etc/ssh/sshd_config.d/50-cloud-init.conf`. FreeIPA users don't have SSH keys deployed, and GSSAPI requires a valid Kerberos ticket, so they cannot authenticate.

## 5. Solution
> Enable password authentication or use GSSAPI with Kerberos ticket.

### Option 1: Enable Password Authentication

```bash
# Via Ansible ad-hoc command
ansible k8s_masters,k8s_workers -m replace -a \
  "path=/etc/ssh/sshd_config.d/50-cloud-init.conf \
   regexp='PasswordAuthentication no' \
   replace='PasswordAuthentication yes'" --become

ansible k8s_masters,k8s_workers -m service -a \
  "name=sshd state=restarted" --become
```

### Option 2: Use GSSAPI with Kerberos Ticket

```bash
# On the source machine (e.g., ansible node)
kinit super_bot
# Enter password

ssh super_bot@k8s-master1.lab.local
# Works via GSSAPI - no password prompt
```

### Option 3: Deploy SSH Keys (Recommended for Automation)

Add SSH public keys to user accounts in FreeIPA or via Ansible.

## 6. Solution Risk
- Risk level: LOW (Option 2, 3) / MEDIUM (Option 1)
- Potential impact: Enabling password auth is less secure than SSH keys or Kerberos

## 7. Impact After Fix
- Observed: FreeIPA users can now SSH to VMs
- HBAC rules working as expected
- Authentication method depends on chosen solution

## 8. Notes

**Verification:**
```bash
# Check what authentication methods are offered
ssh -v super_bot@k8s-master1.lab.local 2>&1 | grep "Authentications that can continue"

# Check sshd config on VM
cat /etc/ssh/sshd_config.d/*.conf | grep PasswordAuthentication

# Test HBAC from FreeIPA server
ipa hbactest --user=super_bot --host=k8s-master1.lab.local --service=sshd
```

**Simple Explanation:**

When you create VMs with cloud-init (like from cloud images), cloud-init runs on first boot and configures the system. One thing it does is disable password login for security - expecting you to use SSH keys instead.

FreeIPA users don't have SSH keys by default. So they can't log in because:
- SSH keys: Not configured
- Password: Disabled by cloud-init
- Kerberos: Works but requires `kinit` first

The fix is either enable passwords or use `kinit` before SSH.

**To override cloud-init, you can either:**
1. Edit 50-cloud-init.conf directly
2. Create a higher-numbered file like `60-allow-password.conf`

**Related:** TS-TF-010 (SSH host key regeneration) - cloud-init behavior on configuration changes

## 9. Workaround (if any)
> Use `kinit <username>` before SSH to get a Kerberos ticket. GSSAPI authentication will work without password prompt.

## References
- [Cloud-Init SSH Configuration](https://cloudinit.readthedocs.io/en/latest/topics/modules.html#ssh)
- [SSHD Config Documentation](https://man.openbsd.org/sshd_config)
