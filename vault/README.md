# HashiCorp Vault Infrastructure

Vault secrets management cluster configuration.

## Structure

```
vault/
├── terraform/              # Vault cluster deployment
├── ansible/                # Vault installation
├── vault-configs/          # Vault HCL configs
│   ├── policies/           # ACL policies
│   ├── auth-methods/       # Auth backends
│   ├── secrets-engines/    # Secret backends
│   └── pki/                # PKI configuration
├── manual-configs/
│   ├── init-keys.txt.gpg   # Encrypted unseal keys
│   └── root-token.txt.gpg  # Encrypted root token
├── docs/
│   ├── ha-setup.md
│   ├── unsealing-procedure.md
│   └── backup-restore.md
├── troubleshooting-cases/
└── scripts/
    ├── unseal-vault.sh
    └── backup-vault.sh
```

## Features

- HA cluster with Raft storage
- PKI secrets engine (internal CA)
- SSH signed certificates
- AppRole for CI/CD
- LDAP auth (FreeIPA integration)

## Getting Started

```bash
# Initialize Vault
vault operator init -key-shares=5 -key-threshold=3

# Unseal
vault operator unseal

# Login
vault login
```

## Security Notes

- **NEVER** commit unencrypted keys
- Store unseal keys separately
- Rotate root token after initial setup

## Documentation

- [HA Setup](docs/ha-setup.md)
- [Unsealing Procedure](docs/unsealing-procedure.md)
- [Backup & Restore](docs/backup-restore.md)
