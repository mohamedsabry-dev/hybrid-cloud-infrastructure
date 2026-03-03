# Ansible Dev Environment Notes

## Ansible Config Location

We used the export approach to ensure Ansible picks up the correct config file regardless of the current working directory:

```bash
echo 'export ANSIBLE_CONFIG=/srv/repo/ansible/dev/ansible.cfg' >> ~/.bashrc
source ~/.bashrc
```

This is added to the ansible node's `~/.bashrc` so it persists across reboots.

## NTP Configuration Disabled

NTP configuration via FreeIPA client (`ipaclient_configure_ntp`) has been disabled due to inconsistency between VMs and LXC containers:

- **VMs (k8s_masters, k8s_workers)**: Chronyd works normally
- **LXC containers (vault_cluster, nginx, ansible, local_runners)**: Chronyd fails because LXC containers inherit time from the Proxmox host and systemd services don't run properly in containers

**Current setting in `group_vars/all.yml`:**
```yaml
ipaclient_no_ntp: true                # Correct variable - skips NTP during enrollment
ipaclient_configure_ntp: false        # Also set for completeness
# ipaclient_ntp_servers:              # Must be commented out
#   - freeipa.lab.local
```

**Note:** The FreeIPA ansible role uses `ipaclient_no_ntp: true` (not `ipaclient_configure_ntp: false`) to actually skip NTP configuration during client enrollment.

**TODO:** Configure NTP separately with direct Ansible playbooks:
- VMs: Configure chronyd pointing to FreeIPA server
- LXC: Skip NTP config (inherits from Proxmox host)

## Git Push from Ansible Node

The ansible node needs write access to push changes back to the repository.

### Deploy Key Configuration

The GitHub deploy key was initially set as **read-only**. Updated the workflow to use write access:

```yaml
# .github/workflows/dev-ansible-full-setup.yml (line ~135)
# Changed from:
-F read_only=true
# To:
-F read_only=false
```

To apply the change:
1. Delete existing deploy key on GitHub (Settings → Deploy keys → Delete `ansible-dev`)
2. Set `DEV_SVC_DEPLOY_KEY_LOCK` to `false` in repo variables
3. Re-run the workflow to re-add key with write access

### Git Pull Strategy

Configure rebase as default pull strategy on the ansible node to avoid merge commits:

```bash
git config --global pull.rebase true
```

This ensures `git pull` automatically rebases local commits on top of remote changes, keeping a clean linear history.

### Typical Workflow for Ansible Admin

```bash
# SSH to ansible node
ssh root@ansible.lab.local

# Pull latest changes
cd /srv/repo
git pull origin dev

# Make edits, test playbooks
vim ansible/dev/inventory/group_vars/all.yml
ansible-playbook ansible/dev/playbooks/freeipa/join-domain.yml

# Commit and push changes back
git add -A
git commit -m "Update configuration"
git push origin dev
```
