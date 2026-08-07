# TS Case 01 — sshd Fails to Start: "no hostkeys available"

## Environment
- Ubuntu Server 26.04 LTS, cloned from a Proxmox golden VM template
- Host: `jenkins-master1`
- Service affected: `ssh.service` (OpenBSD Secure Shell server)

## Symptom
`ssh.service` enters a failed state and restart-loops on boot.

```
sshd[2899]: sshd: no hostkeys available -- exiting
systemd[1]: ssh.service: Control process exited, code=exited, status=1/FAILURE
systemd[1]: Failed to start ssh.service - OpenBSD Secure Shell server.
systemd[1]: ssh.service: Scheduled restart job, restart counter is at 5.
```

## Diagnostic Steps
1. Read the full journal for the failing unit to isolate the actual cause line (not just the systemd wrapper failure):
   ```bash
   journalctl -u ssh.service -b
   ```
   → Identified root line: `sshd: no hostkeys available -- exiting`

2. Confirmed host key files were missing from the expected location:
   ```bash
   ls -la /etc/ssh/ssh_host_*
   ```
   → No `ssh_host_rsa_key`, `ssh_host_ecdsa_key`, or `ssh_host_ed25519_key` present.

3. Checked whether cloud-init's SSH module (`cc_ssh`) had run on this boot:
   ```bash
   journalctl -u cloud-init -b | grep -i ssh
   ```
   → No evidence of `cc_ssh` executing on this boot.

4. Checked cloud-init's per-instance state to determine why the module was skipped:
   ```bash
   ls -la /var/lib/cloud/instances/
   cat /var/lib/cloud/instance/instance-id
   ```
   → Instance-id and semaphore state (`/var/lib/cloud/instance/sem/`) were carried over from the original golden VM build — i.e. this clone was never treated as a "new" instance by cloud-init.

5. Checked whether the systemd unit responsible for key generation was present/enabled:
   ```bash
   systemctl list-unit-files | grep sshd-keygen
   systemctl status 'sshd-keygen@*'
   ```

## Root Cause
The golden image's cleanup/sysprep script deleted the SSH host keys (`/etc/ssh/ssh_host_*`) as part of preparing the image for templating, but did **not** reset cloud-init's instance state (`cloud-init clean`).

Cloud-init tracks completed setup steps per instance-id in `/var/lib/cloud/instances/<id>/` and `/var/lib/cloud/instance/sem/`. Because the semaphore for the `ssh` module (`cc_ssh`) was already marked "done" for the instance-id baked into the template, every VM cloned from that template inherited the same instance-id and the same "already completed" state — so cloud-init skipped host key regeneration entirely on first boot, even though the keys had been deleted. `sshd` then started with an empty `/etc/ssh/`, found no host keys, and refused to start.

## Resolution
Immediate fix on the affected host:
```bash
ssh-keygen -A
systemctl restart ssh.service
systemctl status ssh.service
ss -tlnp | grep :22
```
`ssh-keygen -A` generates any missing host keys for all configured key types using the default paths, equivalent to what `cc_ssh`/`sshd-keygen@.service` normally does on first boot.

## Prevention / Template-Level Fix
Correct order for future golden image prep:
1. Delete SSH host keys (sysprep step, as before).
2. Run `cloud-init clean --logs --seed` to purge instance-id and semaphore state.
3. Optionally clear `/etc/machine-id` (and `/var/lib/dbus/machine-id`) for the same reason — any subsystem that keys behavior off a "unique per instance" ID will otherwise treat every clone as already-provisioned.
4. Shut down and convert to template only after step 2–3.

This ensures every VM cloned from the template is recognized by cloud-init as a genuinely new instance on first boot, so all setup modules (including `cc_ssh`) run fresh.