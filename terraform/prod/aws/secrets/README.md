# AWS Secrets Module — PROD

Provisions AWS Secrets Manager entries consumed by infrastructure automation.
Terraform creates the secret resources with placeholder values; the actual
secret values are populated out-of-band (AWS CLI or console) — see the
setup guide in deployment-docs.

---

## Secrets created

| Secret ID | Purpose |
|-----------|---------|
| `prod/proxmox/terraform-token` | Proxmox API token for Terraform |
| `prod/proxmox/ssh-admin-prod-password` | Proxmox SSH admin password |
| `prod/golden-image/vm-root-password` | VM cloud-init root password |
| `prod/vm/break-glass-password` | Emergency VM recovery password |
| `prod/golden-image/lxc-root-password` | LXC root password |
| `prod/ansible/ssh-public-key` | Ansible SSH public key |
| `prod/local-runner/ssh-public-key` | GitHub runner SSH key |
| `prod/freeipa/admin-password` | FreeIPA admin password |
| `prod/freeipa/dm-password` | FreeIPA Directory Manager password |
| `prod/super_bot/keytab` | super_bot Kerberos keytab (base64) |
| `prod/ansible/vault-password` | Ansible Vault password |

## File structure

| File | Purpose |
|------|---------|
| `main.tf` | Secret resources (identical dev/prod) |
| `outputs.tf` | Secret ARNs and names (identical dev/prod) |
| `variables.tf` | Env-specific configuration |

## Populating secret values

After `terraform apply`, the secrets exist with placeholder values.
Populate them using the procedure in:

  deployment-docs/aws-secrets-setup-guide.txt

That guide has the AWS CLI commands + the canonical secret-by-secret
reference.

## Related

- [`../../../../deployment-docs/aws-secrets-setup-guide.txt`](../../../../deployment-docs/aws-secrets-setup-guide.txt) — value-population commands
- [`../../../../.github/workflows/prod-aws-secrets.yml`](../../../../.github/workflows/prod-aws-secrets.yml) — apply workflow
- [`../../../../github/variables-secrets.md`](../../../../github/variables-secrets.md) — which GitHub workflows consume which secret
