# Shared Resources

Reusable modules, roles, and scripts shared across services.

## Structure

```
shared/
├── terraform-modules/      # Reusable Terraform modules
│   ├── vm-template/        # Standard VM module
│   └── network/            # Network module
├── ansible-roles/          # Reusable Ansible roles
│   ├── common/             # Base OS config
│   ├── security-hardening/ # Security baseline
│   └── monitoring-agent/   # Node exporter
├── scripts/
│   ├── backup-all.sh
│   └── health-check.sh
└── docs/
    └── standards/
        ├── naming-conventions.md
        └── tagging-strategy.md
```

## Terraform Modules

### vm-template

Standard VM provisioning module:

```hcl
module "web_server" {
  source = "../../shared/terraform-modules/vm-template"

  name        = "web-01"
  cpu         = 2
  memory      = 4096
  template    = "rocky-9-template"
}
```

## Ansible Roles

### common

Base configuration applied to all servers:

```yaml
- hosts: all
  roles:
    - common
    - security-hardening
    - monitoring-agent
```

## Standards

- [Naming Conventions](docs/standards/naming-conventions.md)
- [Tagging Strategy](docs/standards/tagging-strategy.md)
