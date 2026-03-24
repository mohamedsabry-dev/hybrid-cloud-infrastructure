# Vault Usage Examples

Manual operations and example commands for HashiCorp Vault.

## On Vault Server

### Login with LDAP
```bash
vault login -method=ldap username=sabry
```

### Enable KV Secrets Engine
```bash
vault secrets enable -path=secret kv-v2
```

### Store a Keytab
```bash
vault kv put secret/freeipa/keytab-super-bot \
  keytab="YOUR_BASE64_STRING" \
  principal="super_bot@LAB.LOCAL"
```

### Retrieve a Secret
```bash
vault kv get secret/freeipa/keytab-super-bot
```

## From Ansible LXC (API Access)

### Setup
```bash
export VAULT_ADDR="https://vault1.lab.local:8200"
```

### Get Token via LDAP Auth
```bash
TOKEN=$(curl -sk $VAULT_ADDR/v1/auth/ldap/login/sabry \
  -d '{"password":"YOUR_PASSWORD"}' | jq -r '.auth.client_token')
```

### Retrieve Keytab and Use It
```bash
# Fetch keytab from Vault
curl -sk -H "X-Vault-Token: $TOKEN" \
  $VAULT_ADDR/v1/secret/data/freeipa/keytab-super-bot \
  | jq -r '.data.data.keytab' | base64 -d > /tmp/super_bot.keytab

# Authenticate with Kerberos
kinit -kt /tmp/super_bot.keytab super_bot@LAB.LOCAL
```

## Related

- Vault playbooks: `ansible/dev/playbooks/vault/`
- Vault cluster: vault1-3.lab.local (10.0.62.10-12)
