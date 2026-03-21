# AWS Secrets Module

Manages AWS Secrets Manager secrets for infrastructure automation.

## Resources Created

| Resource | Name | Purpose |
|----------|------|---------|
| Secret | `prod/proxmox/terraform-token` | Proxmox API token for Terraform |
| Secret | `prod/proxmox/ssh-admin-prod-password` | Proxmox SSH admin password |
| Secret | `prod/golden-image/vm-root-password` | VM cloud-init root password |
| Secret | `prod/vm/break-glass-password` | Emergency VM recovery password |
| Secret | `prod/golden-image/lxc-root-password` | LXC root password |
| Secret | `prod/ansible/ssh-public-key` | Ansible SSH public key |
| Secret | `prod/local-runner/ssh-public-key` | GitHub runner SSH key |
| Secret | `prod/freeipa/admin-password` | FreeIPA admin password |
| Secret | `prod/freeipa/dm-password` | FreeIPA LDAP password |
| Secret | `prod/super_bot/keytab` | Kerberos keytab (base64) |
| Secret | `prod/ansible/vault-password` | Ansible vault password |

## Usage

Secrets are created with placeholder values. Update via AWS CLI:

```bash
aws secretsmanager put-secret-value \
  --secret-id prod/proxmox/terraform-token \
  --secret-string '{"token_id":"xxx","token_secret":"xxx"}'
```

## File Structure

| File | Purpose |
|------|---------|
| `main.tf` | Secret resources (identical dev/prod) |
| `outputs.tf` | Secret ARNs and names (identical dev/prod) |
| `variables.tf` | Environment-specific configuration |
