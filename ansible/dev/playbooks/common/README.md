# Common Playbooks

Cross-platform playbooks that apply to multiple node types.

## Playbooks

| Playbook | Purpose | Target Hosts |
|----------|---------|--------------|
| `pre_setup.yml` | Initial node configuration (mirror fix, SSH, packages) | all / k8s nodes |
| `ntp.yml` | Configure Chrony time synchronization | all |
| `setup_breakglass.yml` | Emergency access user setup | managed_hosts |

## Playbook Details

### pre_setup.yml

Combined playbook for initial node preparation. Includes:

1. **Mirror Fix** - Fixes Rocky Linux repo configuration (required due to old mirror package issues)
2. **SSH Password Auth** - Enables password authentication on VMs (cloud-init overrides this)
3. **Initial Packages** - Installs base packages (vim, git, curl, htop, unzip)

**Run first on fresh nodes before FreeIPA enrollment.**

### ntp.yml

Configures Chrony time synchronization with different configs per node type:

| Node Type | Config | Notes |
|-----------|--------|-------|
| FreeIPA | `chrony_ipa.conf` | Same config as Proxmox host for consistency |
| VMs | `chrony_vm.conf` | Points to FreeIPA as NTP server |
| LXC | (not deployed) | LXC inherits time from Proxmox host kernel |

**Note:** LXC containers cannot run chronyd due to unprivileged nature and shared kernel. Time sync handled by Proxmox host.

### setup_breakglass.yml

**Status: TODO** - To be implemented later.

## Templates

| File | Purpose |
|------|---------|
| `templates/chrony_ipa.conf` | Chrony config for FreeIPA server |
| `templates/chrony_vm.conf` | Chrony config for VMs |
| `templates/chrony_lxc.conf` | Chrony config for LXC (not deployed - see note above) |

## Usage

```bash
# Initial setup on fresh nodes
ansible-playbook -i inventory/first_setup_inventory.ini playbooks/common/pre_setup.yml

# Configure NTP (after FreeIPA enrollment)
ansible-playbook playbooks/common/ntp.yml
```
