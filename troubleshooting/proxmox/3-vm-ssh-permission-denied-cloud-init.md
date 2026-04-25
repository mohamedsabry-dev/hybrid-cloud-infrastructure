# TS-PVE-003 | 2026-03-05 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Proxmox VE / Cloud-Init / SSH
Sub-techs: cloud-init, SSHD drop-in config, FreeIPA, SSSD, GSSAPI, Kerberos
Environment: DEV (lab.local) | All VMs provisioned with cloud-init
Affected: All cloud-init VMs (k8s_masters, k8s_workers)
Re-opened: No

_____________________________________________________________________

[Issue Description]
FreeIPA domain users couldn't SSH to VMs despite correct HBAC rules:

```
ssh super_bot@k8s-master1.lab.local
super_bot@k8s-master1.lab.local: Permission denied (publickey,gssapi-keyex,gssapi-with-mic).
```

No `password` option listed in the error — password authentication was disabled.

_____________________________________________________________________

[Analysis]

Checked authentication methods offered:
```bash
ssh -v super_bot@k8s-master1.lab.local 2>&1 | grep "Authentications that can continue"
```

Found cloud-init creates a drop-in config that overrides main sshd_config:
```bash
cat /etc/ssh/sshd_config.d/50-cloud-init.conf
# PasswordAuthentication no
```

SSH config files in `/etc/ssh/sshd_config.d/` are processed alphabetically. The
main sshd_config sets `PasswordAuthentication yes`, but 50-cloud-init.conf
overrides it to `no`.

FreeIPA users can't authenticate because:
- SSH keys: not configured for FreeIPA users
- Password: disabled by cloud-init
- Kerberos (GSSAPI): works but requires `kinit` first

_____________________________________________________________________

[Final Root Cause]
Cloud-init disables password authentication by default via
`/etc/ssh/sshd_config.d/50-cloud-init.conf`. FreeIPA users don't have SSH keys
deployed, and GSSAPI requires a valid Kerberos ticket, so they can't authenticate.

_____________________________________________________________________

[Final Solution]

Option 1 — Enable password authentication:
```bash
ansible k8s_masters,k8s_workers -m replace -a \
  "path=/etc/ssh/sshd_config.d/50-cloud-init.conf \
   regexp='PasswordAuthentication no' \
   replace='PasswordAuthentication yes'" --become

ansible k8s_masters,k8s_workers -m service -a \
  "name=sshd state=restarted" --become
```

Option 2 — Use GSSAPI with Kerberos ticket:
```bash
kinit super_bot
ssh super_bot@k8s-master1.lab.local
# Works via GSSAPI — no password prompt
```

Option 3 — Deploy SSH keys (recommended for automation): Add SSH public keys to
user accounts in FreeIPA or via Ansible.

Verification:
```bash
ssh -v super_bot@k8s-master1.lab.local 2>&1 | grep "Authentications that can continue"
cat /etc/ssh/sshd_config.d/*.conf | grep PasswordAuthentication
ipa hbactest --user=super_bot --host=k8s-master1.lab.local --service=sshd
```

Verified: Yes — FreeIPA users can SSH to VMs.

_____________________________________________________________________

[Risk Level] LOW (Option 2, 3) / MEDIUM (Option 1)

Enabling password auth is less secure than SSH keys or Kerberos.

_____________________________________________________________________

[References]
- TS-TF-010 — SSH host key regeneration (cloud-init behavior)
