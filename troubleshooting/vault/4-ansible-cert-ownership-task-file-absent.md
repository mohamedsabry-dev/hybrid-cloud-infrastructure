# Case 4: Ownership Task Failing — Cert Not Written Yet

**Component:** HashiCorp Vault | Ansible | Certmonger
**Date:** March 17, 2026

---

## Symptom

"Set correct ownership on TLS files" failed on vault2/3:
```
file is absent, cannot continue
```

---

## Root Cause

The `when` condition was still the old one without `or cert_issuer.rc != 0` so the request task was being skipped on vault2/3 entirely — not a timing issue.

---

## Fix Applied

Updated `when` condition to:
```yaml
when: "'HashiCorp' in cert_issuer.stdout or cert_issuer.rc != 0"
```

---

## Lesson

Always use `-w` with `ipa-getcert` to wait for cert issuance. Ensure `when` conditions handle ALL expected states including missing files, not just the happy path.
