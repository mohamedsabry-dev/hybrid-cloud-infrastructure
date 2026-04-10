# Ansible Playbooks

Configuration management playbooks for POC v1 infrastructure.

## Structure

| Folder | Purpose | Playbooks |
|--------|---------|-----------|
| `ipa/` | FreeIPA identity management | Users, groups, HBAC, sudo rules |
| `cicd/` | Jenkins setup | Installation and configuration |
| `monitor/` | Prometheus monitoring | Node exporter, Prometheus config |
| `os-services/` | OS-level services | Emergency users, Veeam planning |
| `vault/` | HashiCorp Vault | Cluster setup, policies, SSH signer |

## Inventory

The `inventory` file defines all managed hosts:
- `[ipa]` - FreeIPA server
- `[vault]` - Vault cluster (3 nodes)
- `[k8s]` - Kubernetes nodes
- `[cicd]` - Jenkins master
- `[monitor]` - Prometheus server

## Usage

```bash
# Test connectivity
ansible all -i inventory -m ping

# Run playbook
ansible-playbook -i inventory ipa/ipa-01-create-users-groups.yml

# Limit to specific hosts
ansible-playbook -i inventory vault/05-install_vault_binary.yml --limit vault
```

## Authentication

Playbooks use `super_ansible` user with Kerberos authentication.
