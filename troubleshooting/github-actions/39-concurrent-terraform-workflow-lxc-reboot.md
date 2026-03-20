# TS-39: Concurrent Terraform Workflows Caused LXC Reboot and Workflow Failure

## Issue Summary

Vault setup workflow failed with `exit code 255` (SSH connection closed) because concurrent Terraform workflows rebooted the ansible and local_runner LXCs while the vault playbook was running.

## Environment

- **Date:** 2026-03-20
- **Affected Workflows:**
  - `[PROD] Vault - Full Setup` (failed)
  - `[PROD] Ansible - Deploy LXC` (caused reboot)
  - `[PROD] Local Runner - Deploy LXC` (caused reboot)
- **Affected LXCs:**
  - CT 2001 (ansible-prod)
  - CT 2002 (local-runner-prod)
  - CT 2003 (nginx-prod)

## Symptoms

### Initial Error

Vault workflow failed during "Install Vault" task:

```
TASK [Install Vault] ***********************************************************
Connection to 10.0.53.10 closed by remote host.
Error: Process completed with exit code 255.
```

### User Session Disconnection

Interactive SSH sessions to ansible node were also disconnecting unexpectedly:

```
[root@ansible prod]# Connection to ansible-prod closed by remote host.
Connection to ansible-prod closed.
```

---

## Investigation

### Step 1: Check SSH Server Logs

First assumption was SSH timeout. Checked SSH server config:

```bash
grep -E "ClientAlive|TCPKeepAlive" /etc/ssh/sshd_config
```

**Result:** All settings commented out (defaults). Not the cause.

### Step 2: Check SSH Disconnect Logs

```bash
tail -100 /var/log/secure | grep -i "closed\|disconnect\|timeout"
```

**Evidence:**

```
Mar 20 17:45:27 ansible sshd-session[290]: Received disconnect from 192.168.100.223 port 58886:11: disconnected by user
Mar 20 17:45:27 ansible sshd-session[290]: Disconnected from user root 192.168.100.223 port 58886
```

**Analysis:** Disconnect code 11 = `SSH_DISCONNECT_BY_APPLICATION`. Client side closed connection, not server timeout.

### Step 3: Check System Journal for Boot Events

```bash
journalctl --since "1 hour ago" | grep -i ansible
```

**Critical Evidence:**

```
Mar 20 17:45:14 ansible systemd-journald[124]: Journal started
Mar 20 17:45:15 ansible systemd[1]: Startup finished in 1.073s.
```

**Analysis:** The ansible LXC **rebooted** at 17:45:14. This is why SSH connections dropped.

### Step 4: Confirm Reboot History

```bash
last reboot
```

**Evidence:**

```
reboot   system boot  6.17.9-1-pve     Fri Mar 20 17:45   still running
reboot   system boot  6.17.9-1-pve     Fri Mar 20 17:14 - 17:45  (00:30)
```

**Analysis:** LXC rebooted at 17:45, ran for only 30 minutes before rebooting. Confirms the reboot killed the workflow.

### Step 5: Check Proxmox Task Log

Checked Proxmox Web UI → Datacenter → Tasks:

**Evidence:**

| Time | Node | User | Description | Status |
|------|------|------|-------------|--------|
| Mar 20 17:45:11 - 17:45:14 | pve-prod | tf_prod@pve | CT 2001 - Reboot | OK |
| Mar 20 17:52:47 - 17:52:50 | pve-prod | tf_prod@pve | CT 2002 - Reboot | OK |
| Mar 20 17:56:56 - 17:56:59 | pve-prod | tf_prod@pve | CT 2003 - Reboot | OK |

**Critical Finding:** User `tf_prod@pve` = Terraform API token. **Terraform triggered the reboots.**

### Step 6: Identify Concurrent Workflows

Checked GitHub Actions workflow runs:

**Evidence from Local Runner workflow (completed 17:52):**

```
Run terraform apply -auto-approve tfplan
proxmox_virtual_environment_container.local_runner: Modifying... [id=2002]
proxmox_virtual_environment_container.local_runner: Modifications complete after 30s [id=2002]

Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
```

**Analysis:** Terraform was applying mount point changes (`backup = true`) to LXCs, which requires container restart.

---

## Root Cause

### Timeline of Events

| Time | Event | Impact |
|------|-------|--------|
| ~17:40 | Vault Full Setup workflow starts Job 2 (Setup Vault Service) | Playbook running on ansible node |
| ~17:44 | Ansible LXC Deploy workflow runs `terraform apply` | - |
| 17:45:11 | Terraform reboots CT 2001 (ansible) | **SSH connection dropped** |
| 17:45:14 | Ansible LXC starts up | Too late - workflow already failed |
| 17:45:xx | Vault workflow fails with exit code 255 | - |
| ~17:49 | Local Runner LXC Deploy workflow starts | - |
| 17:52:28 | Terraform apply completes on local_runner | - |
| 17:52:50 | Terraform reboots CT 2002 (local_runner) | Would have broken any running workflow |
| 17:56:59 | Terraform reboots CT 2003 (nginx) | - |

### Root Cause Statement

Multiple GitHub workflows ran concurrently:
1. **Vault Setup workflow** - Running ansible playbook that SSHes from local_runner → ansible → vault nodes
2. **Ansible/Local Runner/Nginx Deploy workflows** - Running Terraform to apply mount point config changes

When Terraform applied the `backup = true` mount point configuration change to the LXCs, it triggered container reboots. The ansible LXC reboot at 17:45 killed the SSH session that was running the vault playbook, causing the workflow to fail with exit code 255.

### Why Terraform Rebooted the LXCs

Earlier that day, 16 Terraform files were updated to add `backup = true` to mount point configurations:

```hcl
mount_point {
  path   = "/srv/repo"
  volume = "local-lvm:vm-2001-repo"
  backup = true  # ← This change requires LXC restart
}
```

When these changes were pushed and workflows triggered, Terraform detected the config change and restarted each LXC to apply it.

---

## Resolution

1. **Wait for all mount point update workflows to complete**
2. **Re-run vault setup workflow** - It's idempotent and will continue from where it left off
3. **Check vault nodes status:**
   ```bash
   ssh root@vault1 "rpm -qa | grep vault"
   ```

---

## Prevention

### Option 1: Workflow Dependencies

Use GitHub Actions workflow concurrency to prevent parallel runs:

```yaml
concurrency:
  group: prod-infrastructure
  cancel-in-progress: false
```

### Option 2: Repository Variables as Locks

Use existing lock pattern (`DEV_INFRA_*_LOCK`) to prevent concurrent infrastructure changes.

### Option 3: Operational Awareness

Before running any workflow that uses LXCs:
1. Check if any infrastructure workflows are pending/running
2. Wait for infrastructure changes to complete before running service deployments

### Option 4: Terraform Change Awareness

When making Terraform changes that affect LXC config (mount points, memory, CPU):
1. Understand that these changes will trigger LXC restarts
2. Schedule these changes during maintenance windows
3. Don't run service deployment workflows simultaneously

---

## Key Learnings

1. **Terraform LXC modifications trigger reboots** - Mount point, memory, CPU changes require container restart
2. **Exit code 255 = SSH connection closed** - Look for what killed the connection, not SSH config
3. **Check Proxmox task log** - Shows WHO triggered reboots (user/API token)
4. **`tf_*@pve` user = Terraform** - Immediately indicates Terraform-triggered action
5. **`last reboot` command** - Quick way to confirm container restart times
6. **Journal starts at boot** - `systemd-journald: Journal started` indicates fresh boot

---

## Commands Reference

### Commands Used and What We Looked For

| Command | Purpose | Key Evidence Line |
|---------|---------|-------------------|
| `grep -E "ClientAlive\|TCPKeepAlive" /etc/ssh/sshd_config` | Check if SSH timeout caused disconnect | All commented = not the cause |
| `tail -100 /var/log/secure \| grep -i "closed\|disconnect\|timeout"` | Find SSH disconnect reason | `disconnected by user` with code 11 = client closed |
| `journalctl --since "1 hour ago" \| grep -i ansible` | Check system events on ansible node | `Journal started` = fresh boot |
| `last reboot` | Confirm reboot times | Shows boot at 17:45 |
| Proxmox Web UI → Tasks | Find WHO triggered reboot | `tf_prod@pve` = Terraform |

### Key Log Lines That Revealed the Reboot

**In journalctl output - These two lines indicate fresh boot:**

```
Mar 20 17:45:14 ansible systemd-journald[124]: Journal started    ← BOOT INDICATOR
Mar 20 17:45:15 ansible systemd[1]: Startup finished in 1.073s.   ← BOOT COMPLETE
```

**In /var/log/secure - Disconnect code revealed client-side close:**

```
Received disconnect from 192.168.100.223 port 58886:11: disconnected by user
                                                    ↑
                                         Code 11 = SSH_DISCONNECT_BY_APPLICATION
```

### Useful Grep Filters for Future Troubleshooting

```bash
# Quick check for recent boots (look for Journal started)
journalctl --since "1 hour ago" | grep -i "journal started"

# Find SSH disconnects and their reasons
grep -E "disconnect|closed|timeout" /var/log/secure | tail -20

# Check for system startup sequence
journalctl | grep -E "Startup finished|Journal started|systemd\[1\]: Started"

# Find Terraform-triggered actions in Proxmox (run on Proxmox host)
grep "tf_" /var/log/pve/tasks/index | tail -20

# Quick reboot check
last reboot | head -5

# Check if services restarted (indicates reboot)
journalctl | grep -E "Starting (sshd|NetworkManager|sssd)" | tail -10
```

### Investigation Flow for "Connection Closed" Errors

```
1. Exit code 255? → SSH connection issue
        ↓
2. Check /var/log/secure → "disconnected by user" code 11?
        ↓
   Yes → Client side closed (not server timeout)
        ↓
3. Check journalctl → "Journal started" recently?
        ↓
   Yes → System rebooted!
        ↓
4. Check `last reboot` → Confirm timing
        ↓
5. Check Proxmox Tasks → WHO triggered reboot?
        ↓
   tf_*@pve → Terraform did it
        ↓
6. Check GitHub Actions → Which workflow ran terraform apply?
```

---

## Related Files

- `terraform/prod/proxmox/lxc/ansible/main.tf` - Ansible LXC config
- `terraform/prod/proxmox/lxc/local_runner/main.tf` - Local Runner LXC config
- `.github/workflows/prod-vault-full-setup.yml` - Vault setup workflow
- `troubleshooting/proxmox/38-lxc-mount-point-backup-disabled.md` - Mount point backup change
