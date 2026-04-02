# Case 7: Cert Issuer Check Failing Hard on Missing File

**Component:** Ansible | OpenSSL
**Date:** March 17, 2026

---

## Symptom

Play aborted at "Check current cert issuer" task when `/opt/vault/tls/tls.crt` did not exist.

---

## Root Cause

`openssl x509` returns `rc=1` when file is missing. Task did not have `failed_when: false` so Ansible treated it as fatal.

---

## Fix Applied

1. Added `failed_when: false` to the issuer check task
2. Updated `when` condition to handle `rc != 0` case:
   ```yaml
   when: "'HashiCorp' in cert_issuer.stdout or cert_issuer.rc != 0"
   ```

---

## Lesson

Use `failed_when: false` on probe/check tasks where a non-zero return code is an expected handleable condition, not a true failure.

---

## Commands

```bash
# Check cert issuer
openssl x509 -in /opt/vault/tls/tls.crt -noout -issuer
```
