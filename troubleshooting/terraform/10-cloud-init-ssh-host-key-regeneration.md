# TS-TF-010 | 2026-03-27 | RESOLVED
_____________________________________________________________________

[Info]
Author:
Domain: Terraform / Proxmox / Identity
Sub-techs: cloud-init, SSH host keys, FreeIPA/SSSD KnownHostsCommand,
           Proxmox backup restore, K8s worker recovery
Environment: DEV & PROD | pve-dev, pve-prod | K8s workers (VM 1020, 1021, 1022)
Re-opened: No

_____________________________________________________________________

[Issue Description]
After updating K8s worker VMs via Terraform (adding second network interface and
ip_config per TS-TF-009), SSH connections to all workers fail.

  @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
  @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  Offending ED25519 key in KnownHostsCommand-HOSTNAME:3
  Host key for k8s-worker1 has changed and you have requested strict checking.
  Host key verification failed.

Affected systems:
  Ansible automation (SSH to workers)
  FreeIPA/SSSD host key verification
  Any system with stored known_hosts for workers
  Domain user SSH access (super_bot etc.)

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Traced what changed after the Terraform apply from TS-TF-009.

Sequence of events:
  1. Terraform added second ip_config block to cloud-init initialization
  2. Cloud-init detected configuration change and re-ran initialization on restart
  3. By default, cloud-init regenerates SSH host keys on each run
  4. New SSH host keys generated, overwriting original keys
  5. FreeIPA/SSSD still had old host keys stored via KnownHostsCommand
  6. SSH connections fail — host key does not match stored value

The initialization block change that triggered this:
  ip_config {     ← this was added (TS-TF-009)
    ipv4 {
      address = var.k8s_worker1.ip2
    }
  }

Any change to the cloud-init initialization block causes cloud-init to re-run
on next boot — including the SSH key regeneration step.


# Suspected Root Cause
Cloud-init re-runs when its configuration changes and by default regenerates
SSH host keys on each run. Adding the second ip_config triggered a re-run
on VM restart, generating new host keys and invalidating all stored known_hosts
entries on FreeIPA/SSSD and Ansible.


# More Checks Notes:
Temporary SSH access during incident (bypasses host key check):
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@k8s-worker1
  scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@ansible:/tmp/ssh_host_* /etc/ssh/
  Or: Proxmox noVNC console with root password.

Two recovery options identified:
  Option A: update FreeIPA with new keys (quick, but requires updating all dependents)
  Option B: restore original keys from backup (preferred — no downstream updates needed)


# Suspected Solution
Restore original SSH host keys from Proxmox VM backup. One worker at a time
to maintain K8s pod availability.


# Test
Restored original SSH keys on all 3 workers from NAS backup.
Restarted sshd on each worker after key restoration.

Command:
  ssh root@k8s-worker1  (normal, no workaround flags)

Result: PASS — SSH working normally on all workers, Ansible automation functional,
FreeIPA/SSSD host key verification passing.

_____________________________________________________________________

[Final Root Cause]
Cloud-init re-runs when its configuration changes. Default cloud-init behaviour
includes SSH host key regeneration on each run. Adding a second ip_config block
in the Terraform initialization block triggered a re-run on VM restart, generating
new SSH host keys and breaking all clients that had the original keys stored via
FreeIPA/SSSD KnownHostsCommand.

_____________________________________________________________________

[Final Solution]

Option A — Update FreeIPA with new keys (quick fix, more dependencies):
  ipa host-mod k8s-worker1.lab.local --sshpubkey="$(cat /etc/ssh/ssh_host_ed25519_key.pub)"
  ipa host-mod k8s-worker2.lab.local --sshpubkey="$(cat /etc/ssh/ssh_host_ed25519_key.pub)"
  ipa host-mod k8s-worker3.lab.local --sshpubkey="$(cat /etc/ssh/ssh_host_ed25519_key.pub)"
  sss_cache -E   (on all clients to clear SSSD cache)

Option B — Restore original keys from backup (preferred, used):
  Do one worker at a time to maintain K8s pod availability.

  Per worker procedure:
    1. Shutdown affected K8s worker:
       qm stop 1020

    2. Restore latest NAS backup to a temporary VM ID:
       Proxmox GUI → Backup → Restore → use different VMID

    3. Start temporary VM, SCP original SSH keys to ansible:
       scp root@<temp-vm-ip>:/etc/ssh/ssh_host_* /tmp/worker1_ssh_keys/

    4. Shutdown temporary VM:
       qm stop <temp-vmid>

    5. Start real K8s worker:
       qm start 1020

    6. Access worker using workaround flags, restore original keys:
       ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@k8s-worker1
       mkdir -p /root/ssh_keys_broken_backup
       mv /etc/ssh/ssh_host_* /root/ssh_keys_broken_backup/
       scp root@ansible:/tmp/worker1_ssh_keys/ssh_host_* /etc/ssh/
       systemctl restart sshd

    7. Verify normal SSH works (no workaround flags):
       ssh root@k8s-worker1

    8. Delete temporary VM:
       qm destroy <temp-vmid>

    9. Repeat for worker2 and worker3.
    10. Repeat for production environment.

Prevention — configure golden image to preserve SSH keys:
  Added to proxmox/golden_templates/golden-vm-setup.sh:
    cat > /etc/cloud/cloud.cfg.d/99-preserve-ssh.cfg << EOF
    ssh_deletekeys: false
    ssh_genkeytypes: []
    EOF

  All VMs cloned from this golden image will preserve SSH host keys across
  cloud-init re-runs.

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: VM downtime during key restoration is brief (one worker at a time).
K8s pod availability maintained throughout.

_____________________________________________________________________

[References]
- TS-TF-009 — cloud-init update behaviour (change that triggered this incident)
- /etc/ssh/ssh_config.d/04-ipa.conf — FreeIPA SSH known hosts config
- proxmox/golden_templates/golden-vm-setup.sh — golden image with SSH key preservation

_____________________________________________________________________

[Draft Notes]

Key lessons:
  1. Cloud-init re-runs on configuration change — SSH key regeneration is default
  2. FreeIPA/SSSD KnownHostsCommand requires host keys to match stored values exactly
  3. Always backup SSH host keys before any cloud-init changes
  4. Test cloud-init changes on non-critical VMs before workers
  5. Restore from backup is preferred over updating keys everywhere — fewer dependencies
  6. Do one worker at a time to maintain K8s pod availability
  7. Configure golden image with ssh_deletekeys: false before deploying new VMs

Backup SSH keys before Terraform cloud-init changes:
  ssh root@k8s-worker1 "tar czf /tmp/ssh_host_keys.tar.gz /etc/ssh/ssh_host_*"
  scp root@k8s-worker1:/tmp/ssh_host_keys.tar.gz ./backup/worker1_ssh_keys.tar.gz

Related files:
  terraform/dev/proxmox/vms/k8s_workers/main.tf
  /etc/ssh/ssh_host_*
  proxmox/golden_templates/golden-vm-setup.sh