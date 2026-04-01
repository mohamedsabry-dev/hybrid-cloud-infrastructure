# TS-004: VM SSH Permission Denied - Cloud-Init Override

**Date:** 2026-03-05
**Environment:** DEV (lab.local)
**Affected Systems:** All VMs provisioned with cloud-init (k8s_masters, k8s_workers)
**Status:** RESOLVED

---

## Symptom

FreeIPA domain users cannot SSH to VMs despite correct HBAC rules.

```bash
ssh super_bot@k8s-master1.lab.local
super_bot@k8s-master1.lab.local: Permission denied (publickey,gssapi-keyex,gssapi-with-mic).
```

Note: No `password` option listed in the error.

---

## Root Cause

Cloud-init creates a drop-in configuration file that **overrides** the main sshd_config:

```bash
cat /etc/ssh/sshd_config.d/50-cloud-init.conf
# PasswordAuthentication no
```

This file disables password authentication. The error shows only `publickey,gssapi-*` methods - no `password`.

Since FreeIPA users don't have SSH keys deployed by default, and GSSAPI requires a valid Kerberos ticket, they cannot authenticate.

---

## Solutions

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

---

## Verification

```bash
# Check what authentication methods are offered
ssh -v super_bot@k8s-master1.lab.local 2>&1 | grep "Authentications that can continue"

# Check sshd config on VM
cat /etc/ssh/sshd_config.d/*.conf | grep PasswordAuthentication

# Test HBAC from FreeIPA server
ipa hbactest --user=super_bot --host=k8s-master1.lab.local --service=sshd
```

---

## Simple Explanation

When you create VMs with cloud-init (like from cloud images), cloud-init runs on first boot and configures the system. One thing it does is disable password login for security - expecting you to use SSH keys instead.

FreeIPA users don't have SSH keys by default. So they can't log in because:
- SSH keys: Not configured
- Password: Disabled by cloud-init
- Kerberos: Works but requires `kinit` first

The fix is either enable passwords or use `kinit` before SSH.

---

## Drop-in Config Priority

SSH config files in `/etc/ssh/sshd_config.d/` are processed in alphabetical order. Files that start with lower numbers are loaded first, but **later settings override earlier ones**.

```
/etc/ssh/sshd_config              # Main config (PasswordAuthentication yes)
/etc/ssh/sshd_config.d/50-cloud-init.conf  # Overrides with "no"
```

To override cloud-init, you can either:
1. Edit 50-cloud-init.conf directly
2. Create a higher-numbered file like `60-allow-password.conf`

---

## References

- [Cloud-Init SSH Configuration](https://cloudinit.readthedocs.io/en/latest/topics/modules.html#ssh)
- [SSHD Config Documentation](https://man.openbsd.org/sshd_config)
