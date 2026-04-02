# Case 3: FreeIPA CA Rejected CSR — Hostname Mismatch

**Component:** HashiCorp Vault | FreeIPA | Certmonger
**Date:** March 17, 2026

---

## Symptom

Cert request rejected with:
```
hostname in subject of request 'vault1' does not match name or aliases of principal 'vault/vault1.lab.local@LAB.LOCAL'
```

Status: `CA_REJECTED`, stuck: yes

---

## Root Cause

Certmonger generated CSR with subject `CN=vault1` (short hostname from `ansible_hostname`) but service principal was registered as `vault/vault1.lab.local`. FreeIPA requires subject to match the full principal FQDN.

---

## Fix Applied

1. Added `-N CN={{ inventory_hostname }}` to set subject to FQDN
2. Added `-D {{ inventory_hostname }}` to set DNS SAN to FQDN
3. Ran `getcert stop-tracking` and deleted cert files before retry

---

## Lesson

With `ipa-getcert` and a service principal, always explicitly set `-N` (subject) and `-D` (DNS SAN) to the FQDN. Certmonger defaults to short hostname which fails FreeIPA principal matching.

---

## Commands

```bash
# Stop a stuck certmonger tracking request
getcert stop-tracking -f /opt/vault/tls/tls.crt

# Check certmonger request status
getcert list -f /opt/vault/tls/tls.crt
```
