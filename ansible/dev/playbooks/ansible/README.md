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

## Usage

These playbooks are run automatically by the `ansible-full-setup` workflow after the Ansible node is provisioned.

```bash
# Manual run (from ansible node)
ansible-playbook playbooks/ansible/ansible_setup.yml
ansible-playbook playbooks/ansible/test.yml
```
