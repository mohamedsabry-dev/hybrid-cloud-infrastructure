# FreeIPA Infrastructure

FreeIPA identity management server configuration.

## Structure

```
freeipa/
├── terraform/              # VM deployment
├── ansible/                # FreeIPA installation & config
│   ├── playbooks/
│   │   ├── server-install/
│   │   ├── replica-setup/
│   │   └── client-config/
│   └── roles/
├── manual-configs/
│   ├── initial-setup/
│   └── ldif-exports/
├── docs/
│   ├── installation-guide.md
│   ├── user-management.md
│   └── dns-integration.md
├── troubleshooting-cases/
└── scripts/
    ├── user-creation.sh
    └── backup-ipa.sh
```

## Services Provided

- LDAP directory
- Kerberos authentication
- DNS management
- Certificate authority
- HBAC (Host-based access control)
- Sudo rules

## Getting Started

```bash
# Deploy IPA server
cd ansible/playbooks/server-install
ansible-playbook -i inventory install-ipa.yml

# Join client to domain
cd ../client-config
ansible-playbook -i inventory join-domain.yml
```

## Documentation

- [Installation Guide](docs/installation-guide.md)
- [User Management](docs/user-management.md)
- [DNS Integration](docs/dns-integration.md)
