# Secrets Management

## Initial Setup

After running `terraform apply`, update placeholder values:
```bash
# Proxmox API Token
aws secretsmanager put-secret-value \
  --secret-id dev/proxmox/terraform-token \
  --secret-string '{"token_id":"tf_dev@pve!terraform","token_secret":"YOUR_ACTUAL_TOKEN"}'

# Proxmox SSH Password
aws secretsmanager put-secret-value \
  --secret-id dev/proxmox/ssh-admin-password \
  --secret-string 'YOUR_ACTUAL_PASSWORD'

# VM Root Password
aws secretsmanager put-secret-value \
  --secret-id dev/proxmox/vm-root-password \
  --secret-string 'YOUR_ACTUAL_PASSWORD'

# Gandalf Break-Glass Password
aws secretsmanager put-secret-value \
  --secret-id dev/vm/gandalf-password \
  --secret-string 'YOUR_ACTUAL_PASSWORD'
```