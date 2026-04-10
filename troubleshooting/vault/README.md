# Vault Troubleshooting Cases

Documentation of HashiCorp Vault issues encountered in the hybrid cloud infrastructure.

---

## Cases

| # | File | Date | Issue | Root Cause |
|---|------|------|-------|------------|
| 1 | [vault-cluster-initial-setup-investigation](1-vault-cluster-initial-setup-investigation.md) | 2026-03-17 | 8 issues during initial deployment | GPG keys, certmonger, CSR, Ansible patterns |
| 2 | [freeipa-vip-certificate-san-managedby](2-freeipa-vip-certificate-san-managedby.md) | 2026-03-29 | VIP SAN cert request rejected | Missing managedby permissions for both host AND service |
| 3 | [vault-kms-credentials-overwrite-empty-vars](3-vault-kms-credentials-overwrite-empty-vars.md) | 2026-03-29 | Vault fails to start - KMS credentials empty | Manual playbook run bypassed secret injection |
| 4 | [vault-agent-injector-k8s-tls-ca-setup](4-vault-agent-injector-k8s-tls-ca-setup.md) | 2026-03-30 | Vault Agent TLS and template errors | Wrong annotations, Go template hyphen handling |

---

## Quick Reference

### Initial Setup (Case 1)
8 issues resolved during initial deployment:
- GPG signature validation
- Certmonger --force flag
- FreeIPA CA CSR hostname mismatch
- Ansible cert check / ownership tasks
- Vault TLS IP SAN error
- Shell expansion wrong node
- RPM post-install ordering

### VIP Certificate (Case 2)
```bash
# Check managedby relationships
ipa host-show vault.lab.local --all | grep -i "managed by"
ipa service-show vault/vault.lab.local --all | grep -i "managed by"

# Add service managedby (use service-mod, not service-add-managedby)
ipa service-mod vault/vault.lab.local --addattr=managedby=fqdn=vault1.lab.local,cn=computers,cn=accounts,dc=lab,dc=local
```

### KMS Credentials (Case 3)
```yaml
# Safeguard for credential deployment
- name: Deploy vault credentials
  template: ...
  when:
    - vault_aws_access_key_id is defined
    - vault_aws_access_key_id | length > 0
```

### Vault Agent Injector (Case 4)
```yaml
# Correct annotations for TLS CA
vault.hashicorp.com/tls-secret: "vault-ca"        # NOT agent-extra-secret
vault.hashicorp.com/ca-cert: "/vault/tls/ca.crt"  # NOT /vault/secrets/

# Hyphenated keys in templates
{{ index .Data.data "login-password" }}           # NOT .Data.data.login-password
```

---

## Environment

- **Vault Cluster:** vault1/2/3.lab.local
- **VIP:** vault.lab.local (10.0.62.100)
- **TLS:** FreeIPA CA signed certificates
- **Auto-Unseal:** AWS KMS

