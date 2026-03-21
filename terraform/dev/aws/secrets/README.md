# AWS Secrets Module

Manages AWS Secrets Manager secrets for infrastructure automation.

## Resources Created

| Resource | Name | Purpose |
|----------|------|---------|
| Secret | `dev/proxmox/terraform-token` | Proxmox API token for Terraform |
| Secret | `dev/proxmox/ssh-admin-dev-password` | Proxmox SSH admin password |
| Secret | `dev/golden-image/vm-root-password` | VM cloud-init root password |
| Secret | `dev/vm/break-glass-password` | Emergency VM recovery password |
| Secret | `dev/golden-image/lxc-root-password` | LXC root password |
| Secret | `dev/ansible/ssh-public-key` | Ansible SSH public key |
| Secret | `dev/local-runner/ssh-public-key` | GitHub runner SSH key |
| Secret | `dev/freeipa/admin-password` | FreeIPA admin password |
| Secret | `dev/freeipa/dm-password` | FreeIPA LDAP password |
| Secret | `dev/super_bot/keytab` | Kerberos keytab (base64) |
| Secret | `dev/ansible/vault-password` | Ansible vault password |

## Usage

Secrets are created with placeholder values. Update via AWS CLI:

```bash
aws secretsmanager put-secret-value \
  --secret-id dev/proxmox/terraform-token \
  --secret-string '{"token_id":"xxx","token_secret":"xxx"}'
```

## File Structure

| File | Purpose |
|------|---------|
| `main.tf` | Secret resources (identical dev/prod) |
| `outputs.tf` | Secret ARNs and names (identical dev/prod) |
| `variables.tf` | Environment-specific configuration |
