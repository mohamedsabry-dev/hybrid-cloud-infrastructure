# TS-60: Cloud-Init SSH Host Key Regeneration After Terraform Update

## Problem Statement
After updating K8s worker VMs via Terraform (adding second network interface and ip_config),
cloud-init regenerated SSH host keys, breaking SSH authentication for all clients that had
the original host keys stored (FreeIPA/SSSD, known_hosts, etc.).

## Environment
- Proxmox: pve-dev, pve-prod
- K8s Workers: 1020, 1021, 1022
- Authentication: FreeIPA with SSSD (KnownHostsCommand)
- Affected: All SSH connections to workers

## Root Cause

### What Happened
1. Terraform updated cloud-init configuration (added second `ip_config` for storage network)
2. Cloud-init detected configuration change and re-ran initialization
3. By default, cloud-init regenerates SSH host keys on each run
4. New SSH host keys were generated, overwriting the original keys
5. FreeIPA/SSSD still had old host keys stored
6. SSH connections failed with "REMOTE HOST IDENTIFICATION HAS CHANGED" error

### Terraform Configuration (initialization block)
```hcl
initialization {
  datastore_id = var.disks.os_disk.datastore_id

  user_account {
    keys     = [var.ansible_ssh_public_key]
    username = "root"
    password = var.vm_root_password
  }

  ip_config {
    ipv4 {
      address = var.k8s_worker1.ip
      gateway = var.k8s_worker1.gateway
    }
  }

  ip_config {      # <-- This was added, triggering cloud-init re-run
    ipv4 {
      address = var.k8s_worker1.ip2
    }
  }

  dns {
    servers = var.dns_servers
    domain  = var.search_domain
  }
}
```

## Impact

### Symptoms
```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
...
Offending ED25519 key in KnownHostsCommand-HOSTNAME:3
Host key for k8s-worker1 has changed and you have requested strict checking.
Host key verification failed.
```

### Affected Systems
- Ansible automation (SSH to workers)
- FreeIPA/SSSD host key verification
- Any system with stored known_hosts for workers
- Domain user SSH access (super_bot, etc.)

## Workaround (Temporary Access)

To access VMs while keys are mismatched:
```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@k8s-worker1
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@k8s-worker2
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@k8s-worker3
```

To SCP files while keys are mismatched:
```bash
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@ansible:/tmp/ssh_host_* /etc/ssh/
```

Or via Proxmox console (noVNC) with root password.

## Solution Options

### Option A: Update FreeIPA with New Keys (Quick Fix)
If many systems depend on the keys, update the new keys everywhere:

```bash
# On each worker (after kinit)
ipa host-mod k8s-worker1.lab.local --sshpubkey="$(cat /etc/ssh/ssh_host_ed25519_key.pub)"
ipa host-mod k8s-worker2.lab.local --sshpubkey="$(cat /etc/ssh/ssh_host_ed25519_key.pub)"
ipa host-mod k8s-worker3.lab.local --sshpubkey="$(cat /etc/ssh/ssh_host_ed25519_key.pub)"

# Clear SSSD cache on clients
sss_cache -E
```

### Option B: Restore Original Keys from Backup (Preferred)
Rollback to original keys so no downstream updates needed:

**Procedure (per worker, one at a time to maintain pod availability):**

1. **Shutdown the affected K8s worker VM** (avoid network conflict)
   ```bash
   qm stop 1020  # worker1
   ```

2. **Restore latest backup from NAS to new temporary VM ID**
   - Proxmox GUI: Backup → Restore to different VMID

3. **Start temporary VM, SCP the SSH host keys to ansible**
   ```bash
   # From ansible or any accessible host
   scp root@<temp-vm-ip>:/etc/ssh/ssh_host_* /tmp/worker1_ssh_keys/
   ```

4. **Shutdown the temporary restored VM**
   ```bash
   qm stop <temp-vmid>
   ```

5. **Start the real K8s worker**
   ```bash
   qm start 1020
   ```

6. **Access worker with workaround and restore keys**
   ```bash
   ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@k8s-worker1

   # Backup current (broken) keys
   mkdir -p /root/ssh_keys_broken_backup
   mv /etc/ssh/ssh_host_* /root/ssh_keys_broken_backup/

   # Copy original keys from ansible
   scp root@ansible:/tmp/worker1_ssh_keys/ssh_host_* /etc/ssh/

   # Verify permissions (should be preserved from backup)
   ls -la /etc/ssh/ssh_host_*

   # Restart SSH service
   systemctl restart sshd
   ```

7. **Verify normal SSH works**
   ```bash
   # From ansible
   ssh root@k8s-worker1  # Should work without workaround
   ```

8. **Delete temporary VM**
   ```bash
   qm destroy <temp-vmid>
   ```

9. **Repeat for worker2 and worker3**

10. **Repeat for production environment**

## Prevention Measures

### 1. Configure Golden Image to Preserve SSH Keys (Recommended)
Add to golden image template before converting to template:
```bash
cat > /etc/cloud/cloud.cfg.d/99-preserve-ssh.cfg << EOF
ssh_deletekeys: false
ssh_genkeytypes: []
EOF
```
This is configured in `proxmox/golden_templates/golden-vm-setup.sh`.
All VMs cloned from this template will preserve their SSH host keys.

### 2. Backup SSH Keys Before Terraform Changes
```bash
# Before applying cloud-init changes
ssh root@k8s-worker1 "tar czf /tmp/ssh_host_keys.tar.gz /etc/ssh/ssh_host_*"
scp root@k8s-worker1:/tmp/ssh_host_keys.tar.gz ./backup/worker1_ssh_keys.tar.gz
```

## Lessons Learned

1. Cloud-init re-runs when configuration changes, regenerating SSH host keys by default
2. FreeIPA/SSSD KnownHostsCommand requires host keys to match stored values
3. Always have recent backups before making cloud-init changes
4. Test cloud-init changes on non-critical VMs first
5. Consider disabling SSH key regeneration in cloud-init config
6. Restore from backup is preferred over updating keys everywhere (fewer dependencies)
7. Do one worker at a time to maintain K8s pod availability

## Related Files
- `terraform/dev/proxmox/vms/k8s_workers/main.tf` - Terraform VM config
- `/etc/ssh/ssh_config.d/04-ipa.conf` - FreeIPA SSH known hosts config
- `/etc/ssh/ssh_host_*` - SSH host key files

## Date
2026-03-27
