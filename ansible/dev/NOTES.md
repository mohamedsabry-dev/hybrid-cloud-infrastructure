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
