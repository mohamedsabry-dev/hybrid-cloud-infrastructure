# Automation

> **Archived PoC v1 material** — retired infrastructure, not the current project.
> See [`../README.md`](../README.md) for the retirement story and the current stack.
> Kept as-is for portfolio reference.

Scripts and playbooks for infrastructure automation (PoC v1 era — VMware-based).

## Structure

```
automation/
├── ansible/          # Ansible playbooks by service
│   ├── ipa/          # FreeIPA identity management
│   ├── cicd/         # Jenkins CI/CD
│   ├── monitor/      # Prometheus monitoring
│   ├── os-services/  # OS-level services
│   └── vault/        # HashiCorp Vault
└── scripts/          # Shell scripts
    ├── bash/         # Bash utilities
    └── powershell/   # PowerShell DR automation
```

## Quick Start

```bash
# Run ansible playbook
cd ansible
ansible-playbook -i inventory ipa/ipa-01-create-users-groups.yml

# Run bash script
bash scripts/bash/create-emergency-user.sh
```

## Related

- [Ansible inventory](ansible/inventory)
- [Vault init guide](ansible/vault/07-vault_init_guide.txt)
