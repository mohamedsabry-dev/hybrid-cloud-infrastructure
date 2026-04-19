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
4. **pip** - Installs python3-pip (required for Python packages)
5. **hvac** - Installs hvac Python library (required for HashiCorp Vault Ansible modules)

**Run first on fresh nodes before FreeIPA enrollment.**

#### Idempotency

The mirror fix section is idempotent:
- Checks if `#mirrorlist=` exists in repo file (fix already applied)
- Only runs sed commands if not already fixed
- Only cleans/rebuilds cache when changes made
- Re-running shows `skipped` instead of `changed`

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

## When these run

- `pre_setup.yml` — runs on fresh nodes BEFORE FreeIPA enrollment. Uses the
  bootstrap inventory (IP + root + SSH key). Invoked as a preparatory step
  by the full-setup workflows (`{env}-ansible-full-setup.yml`,
  `{env}-freeipa-full-setup.yml`, etc.).
- `ntp.yml` — runs AFTER FreeIPA enrollment. Uses the production inventory.
  Run as part of the post-enrollment configuration pass or whenever the
  chrony config changes.
- `setup_breakglass.yml` — **TODO**, not yet implemented.

For the broader run order see [`../freeipa/freeipa-setup-guide.txt`](../freeipa/freeipa-setup-guide.txt)
and the top-level sequenced guides under `deployment-docs/`.
