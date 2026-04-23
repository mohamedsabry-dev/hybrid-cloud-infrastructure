# Ansible Node Playbooks

Playbooks for configuring the Ansible control node itself.

## Playbooks

| Playbook | Purpose |
|----------|---------|
| `ansible_setup.yml` | Install initial packages and Ansible Galaxy collections |
| `test.yml` | Test connectivity to all nodes (used in workflow validation) |

## Templates

| File | Purpose |
|------|---------|
| `templates/requirements.yml` | Ansible Galaxy collections required by playbooks |

## Collections Installed

- `freeipa.ansible_freeipa` - FreeIPA management
- `community.hashi_vault` - HashiCorp Vault integration
- `community.general` - General utilities (timezone, etc.)
- `community.crypto` - Cryptographic operations
- `ansible.posix` - POSIX-specific functionality

## When these run

- Both playbooks run automatically by the `{env}-ansible-full-setup.yml`
  workflow after the Ansible LXC is provisioned.
- Manual re-run (from the Ansible node itself): `ansible_setup.yml` if the
  Galaxy requirements change; `test.yml` any time to validate connectivity
  to the fleet.
