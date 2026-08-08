# TS Case 07 — sshd Fails to Start: "no hostkeys available"

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

## Contributing Factor — Golden Image Config (found during rebuild)
A second, independent issue was found in `golden-vm-setup-ubuntu.sh` while preparing to rebuild the template, which would have blocked key generation even after the `cloud-init clean` fix above.

The script's `/etc/cloud/cloud.cfg.d/99-preserve-ssh.cfg` block (added previously per **TS-TF-010**, to stop cloud-init from regenerating/overwriting host keys on config-change re-runs) was set to:
```yaml
ssh_deletekeys: false
ssh_genkeytypes: []
```
`ssh_genkeytypes: []` tells `cc_ssh` there are no key types to generate — so on a genuinely fresh clone (correct instance-id, no semaphore skip, keys actually absent), it still generates **zero** keys, every time. This setting was the correct fix for TS-TF-010's problem (existing keys being overwritten) but was an over-correction: `ssh_deletekeys: false` alone already prevents overwriting existing keys, without needing to also empty the generation list. The empty list broke first-boot generation as an unintended side effect.

Corrected config:
```yaml
ssh_deletekeys: false
ssh_genkeytypes: ['rsa', 'ecdsa', 'ed25519']
```
This preserves TS-TF-010's protection (keys aren't touched if they already exist) while restoring correct first-boot generation on fresh clones.

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
5. Confirm `99-preserve-ssh.cfg` uses an explicit `ssh_genkeytypes` list (`['rsa', 'ecdsa', 'ed25519']`), not `[]` — see Contributing Factor above.

This ensures every VM cloned from the template is recognized by cloud-init as a genuinely new instance on first boot, so all setup modules (including `cc_ssh`) run fresh and generate keys correctly.

## Cross-References
- **TS-TF-010** — original incident that introduced the `99-preserve-ssh.cfg` block, to stop cloud-init from overwriting SSH host keys on config-change re-runs (e.g. Terraform `ip_config` changes). That case's "Prevention" section listed `ssh_genkeytypes: []` as the verified fix — **this has since been superseded**; the empty list is what caused the present case. TS-TF-010 should be updated/annotated to point here and to the corrected config, so its "Verified: Yes" note isn't taken at face value in isolation.