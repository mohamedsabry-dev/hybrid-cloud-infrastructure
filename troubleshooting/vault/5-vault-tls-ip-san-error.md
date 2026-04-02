# Case 5: vault status Defaulting to 127.0.0.1 — TLS IP SAN Error

**Component:** HashiCorp Vault | TLS
**Date:** March 17, 2026

---

## Symptom

```
tls: failed to verify certificate for 127.0.0.1 because it doesn't contain any IP SANs
```

---

## Root Cause

Vault CLI defaults to `https://127.0.0.1:8200` when `VAULT_ADDR` is not set. Cert was issued for `vault1.lab.local` not `127.0.0.1`. IP SANs were deliberately not included.

---

## Fix Applied

Deployed `/etc/profile.d/vault.sh` on all nodes via Ansible:
```bash
export VAULT_ADDR=https://{{ inventory_hostname }}:8200
export VAULT_CACERT=/etc/ipa/ca.crt
```

---

## Lesson

Always set `VAULT_ADDR` explicitly. Use `VAULT_CACERT` pointing to the signing CA rather than `VAULT_SKIP_VERIFY=1`.

---

## Commands

```bash
# Check Vault status across all nodes
ansible vault_cluster -m command \
    -a "bash -c 'source /etc/profile.d/vault.sh && vault status'" \
    -i inventory/inventory.ini
```
