# Vault Playbooks

HashiCorp Vault cluster deployment and configuration.

## Playbooks

| File | Purpose |
|------|---------|
| `01-node_preflight_check.yml` | Pre-deployment checks |
| `02-vault_fw_check.yml` | Firewall configuration |
| `03-vault_mesh_check.yml` | Cluster mesh connectivity |
| `04-vault_storage_check.yml` | Storage backend checks |
| `05-install_vault_binary.yml` | Install Vault binary |
| `06-configure_vault_raft.yml` | Configure Raft storage |

## Guides

| File | Purpose |
|------|---------|
| `07-vault_init_guide.txt` | Initialization and unsealing |
| `08-guide-set-users.txt` | User and policy setup |
| `09-internet-restriction.txt` | Network restrictions |

## Policies

- `admin-policy.hcl` - Admin access policy
- `operator-policy.hcl` - Operator access policy

## Templates

- `vault.hcl.j2` - Vault configuration template

## Deployment Order

1. Run preflight checks (01-04)
2. Install binary (05)
3. Configure Raft (06)
4. Initialize cluster (see 07-vault_init_guide.txt)
5. Create users and policies (see 08-guide-set-users.txt)
