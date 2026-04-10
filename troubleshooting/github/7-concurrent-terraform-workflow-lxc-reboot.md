# TS-GH-007 | 2026-03-20 | RESOLVED

## 1. Context
- System: GitHub Actions workflows + Terraform + Proxmox LXC
- Environment: Prod (pve-prod, CT 2001/2002/2003)
- Related components: Vault setup workflow, Ansible/Local Runner deploy workflows

## 2. Issue
- Symptom: Vault setup workflow failed with `exit code 255` (SSH connection closed). Interactive SSH sessions also disconnecting unexpectedly.
- Error:
```
TASK [Install Vault] ***********************************************************
Connection to 10.0.53.10 closed by remote host.
Error: Process completed with exit code 255.
```

```
[root@ansible prod]# Connection to ansible-prod closed by remote host.
Connection to ansible-prod closed.
```

## 3. Analysis

**Check 1: SSH server config (timeout?)**
```bash
grep -E "ClientAlive|TCPKeepAlive" /etc/ssh/sshd_config
```
Finding: All settings commented out (defaults). Not the cause.

**Check 2: SSH disconnect logs**
```bash
tail -100 /var/log/secure | grep -i "closed\|disconnect\|timeout"
```
```
Mar 20 17:45:27 ansible sshd-session[290]: Received disconnect from 192.168.100.223 port 58886:11: disconnected by user
Mar 20 17:45:27 ansible sshd-session[290]: Disconnected from user root 192.168.100.223 port 58886
```
Finding: Disconnect code 11 = `SSH_DISCONNECT_BY_APPLICATION`. Client side closed, not server timeout.

**Check 3: System journal for boot events**
```bash
journalctl --since "1 hour ago" | grep -i ansible
```
```
Mar 20 17:45:14 ansible systemd-journald[124]: Journal started
Mar 20 17:45:15 ansible systemd[1]: Startup finished in 1.073s.
```
Finding: The ansible LXC **rebooted** at 17:45:14.

**Check 4: Reboot history**
```bash
last reboot
```
```
reboot   system boot  6.17.9-1-pve     Fri Mar 20 17:45   still running
reboot   system boot  6.17.9-1-pve     Fri Mar 20 17:14 - 17:45  (00:30)
```
Finding: LXC ran only 30 minutes before rebooting.

**Check 5: Proxmox task log**

| Time | Node | User | Description | Status |
|------|------|------|-------------|--------|
| Mar 20 17:45:11 - 17:45:14 | pve-prod | tf_prod@pve | CT 2001 - Reboot | OK |
| Mar 20 17:52:47 - 17:52:50 | pve-prod | tf_prod@pve | CT 2002 - Reboot | OK |
| Mar 20 17:56:56 - 17:56:59 | pve-prod | tf_prod@pve | CT 2003 - Reboot | OK |

Finding: User `tf_prod@pve` = Terraform API token. **Terraform triggered the reboots.**

## 4. Root Cause
> Multiple GitHub workflows ran concurrently. Terraform workflows applied `backup = true` mount point changes to LXCs, which requires container restart. The ansible LXC reboot at 17:45 killed the SSH session running the vault playbook, causing exit code 255.

**Why Terraform rebooted LXCs:**
```hcl
mount_point {
  path   = "/srv/repo"
  volume = "local-lvm:vm-2001-repo"
  backup = true  # ← This change requires LXC restart
}
```

## 5. Solution
> Wait for infrastructure workflows to complete before running service deployments. Use concurrency controls.

**Immediate fix:**
1. Wait for all mount point update workflows to complete
2. Re-run vault setup workflow (idempotent)

**Prevention - Option 1: Workflow concurrency**
```yaml
concurrency:
  group: prod-infrastructure
  cancel-in-progress: false
```

**Prevention - Option 2: Repository lock variables**
Use existing lock pattern (`DEV_INFRA_*_LOCK`) to prevent concurrent infrastructure changes.

**Prevention - Option 3: Operational awareness**
Before running service workflows, check if infrastructure workflows are pending/running.

## 6. Solution Risk
- Risk level: LOW
- Potential impact: Concurrency controls may queue workflows longer

## 7. Impact After Fix
- Observed: Vault setup workflow succeeded on re-run
- No concurrent infrastructure changes during service deployments

## 8. Notes

**Investigation flow for "Connection Closed" errors:**
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

**Key learnings:**
1. Terraform LXC modifications (mount points, memory, CPU) trigger reboots
2. Exit code 255 = SSH connection closed - look for what killed it
3. `tf_*@pve` user = Terraform action
4. `last reboot` is fastest way to confirm container restart

## 9. Workaround (if any)
> Re-run failed workflow after infrastructure changes complete. Vault/Ansible playbooks are idempotent.
