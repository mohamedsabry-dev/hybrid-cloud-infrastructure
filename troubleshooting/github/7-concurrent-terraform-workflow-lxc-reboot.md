# TS-GH-007 | 2026-03-20 | RESOLVED
_____________________________________________________________________

[Info]
Domain: GitHub Actions / Terraform
Sub-techs: Terraform LXC mount points, GitHub Actions concurrency, SSH disconnect, Proxmox API
Environment: Prod | pve-prod | CT 2001/2002/2003
Re-opened: No

_____________________________________________________________________

[Issue Description]
Vault setup workflow failed with exit code 255 — SSH connection closed mid-playbook.
Interactive SSH sessions to ansible-prod also disconnecting unexpectedly at same time.

  TASK [Install Vault]
  Connection to 10.0.53.10 closed by remote host.
  Error: Process completed with exit code 255.

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
First checked SSH server config for timeout settings — ruled out server-side disconnect.

Command:
  grep -E "ClientAlive|TCPKeepAlive" /etc/ssh/sshd_config

Output:
  All settings commented out (defaults). Not the cause.

Checked SSH logs for disconnect reason:

Command:
  tail -100 /var/log/secure | grep -i "closed|disconnect|timeout"

Output:
  Received disconnect from 192.168.100.223 port 58886:11: disconnected by user
  Disconnect code 11 = SSH_DISCONNECT_BY_APPLICATION — client side closed, not server timeout.

Checked system journal for what happened at disconnect time:

Command:
  journalctl --since "1 hour ago" | grep -i ansible

Output:
  Mar 20 17:45:14 ansible systemd-journald[124]: Journal started
  Mar 20 17:45:15 ansible systemd[1]: Startup finished in 1.073s.

The ansible LXC rebooted at 17:45:14 — right when the SSH session dropped.

Confirmed reboot timing:

Command:
  last reboot

Output:
  reboot  system boot  6.17.9-1-pve  Fri Mar 20 17:45  still running
  reboot  system boot  6.17.9-1-pve  Fri Mar 20 17:14 - 17:45  (00:30)

LXC had only been running 30 minutes before it rebooted.


# Suspected Root Cause
Something triggered a reboot of the ansible LXC at exactly the time the vault
playbook was running. Needed to identify what triggered the reboot.


# More Checks Notes:
Checked Proxmox task log to find who triggered the reboot.

Output:
  Mar 20 17:45:11 - 17:45:14  pve-prod  tf_prod@pve  CT 2001 - Reboot  OK
  Mar 20 17:52:47 - 17:52:50  pve-prod  tf_prod@pve  CT 2002 - Reboot  OK
  Mar 20 17:56:56 - 17:56:59  pve-prod  tf_prod@pve  CT 2003 - Reboot  OK

User tf_prod@pve = Terraform API token. Terraform triggered all three reboots.

Terraform was applying a mount point change with backup = true:
  mount_point {
    path   = "/srv/repo"
    volume = "local-lvm:vm-2001-repo"
    backup = true   ← this change requires LXC restart
  }

Multiple GitHub workflows ran concurrently — Terraform infrastructure workflow
applied mount point changes while vault setup workflow was mid-execution over SSH.
Terraform reboot killed the SSH session.


# Suspected Root Cause
Concurrent GitHub workflows. Terraform applied backup = true mount point changes
to LXCs — this requires a container restart. The reboot killed the active SSH
session running the vault playbook. Exit code 255 = SSH connection lost.


# More Checks Notes:
Confirmed which GitHub workflow triggered the Terraform apply by cross-referencing
workflow run timestamps with Proxmox task log timestamps.

Output:
  Timestamps matched — Terraform infrastructure workflow ran concurrently with
  vault setup workflow, no concurrency controls in place.


# Suspected Solution
Wait for all infrastructure workflows to complete before running service deployments.
Re-run vault setup workflow — playbook is idempotent.


# Test
Waited for mount point update workflows to finish, re-ran vault setup workflow.

Result: PASS — vault setup completed successfully with no SSH disconnects.

_____________________________________________________________________

[Final Root Cause]
Multiple GitHub workflows ran concurrently without concurrency controls. Terraform
infrastructure workflow applied backup = true to LXC mount points, which requires
container restart. The ansible LXC (CT 2001) rebooted at 17:45:14 while the vault
setup playbook was actively running over SSH. The reboot closed the SSH connection
mid-task — exit code 255.

_____________________________________________________________________

[Final Solution]
Immediate: waited for infrastructure workflows to complete, re-ran vault setup.
Playbooks are idempotent — safe to re-run.

Prevention options:

  Option 1: Workflow concurrency groups
    concurrency:
      group: prod-infrastructure
      cancel-in-progress: false
    (queues workflows instead of running in parallel)

  Option 2: Repository lock variables
    Use existing lock pattern (DEV_INFRA_*_LOCK) to prevent concurrent
    infrastructure changes during service deployments.

  Option 3: Operational awareness
    Before running service workflows, confirm no infrastructure workflows
    are pending or running.

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Concurrency controls may queue workflows longer but prevent mid-run
infrastructure changes from killing active SSH sessions.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Terraform LXC changes that trigger reboots:
  - mount_point backup = true/false changes
  - Memory or CPU changes
  - Other resource modifications depending on Proxmox provider behavior

Investigation flow for exit code 255 / connection closed errors:
  1. Exit code 255         → SSH connection dropped, not a task failure
  2. /var/log/secure       → disconnect code 11 = client side closed
  3. journalctl            → "Journal started" recently = system rebooted
  4. last reboot           → confirm timing matches disconnect
  5. Proxmox task log      → who triggered the reboot
  6. tf_*@pve user         → Terraform did it
  7. GitHub Actions runs   → which workflow ran terraform apply concurrently

Key: tf_*@pve in Proxmox task log = Terraform API token action.
     last reboot is the fastest way to confirm container restart.