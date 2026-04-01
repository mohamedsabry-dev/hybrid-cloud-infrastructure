# Case 26: ipa-getcert --force Flag Not Recognized

**Component:** HashiCorp Vault | Certmonger | Rocky Linux 10
**Date:** March 17, 2026

---

## Symptom

`ipa-getcert request` failed on all 3 nodes with:
```
unrecognized option --force
```

---

## Root Cause

`--force` does not exist in certmonger 0.79.20-3.el10 installed on Rocky Linux 10. Incorrectly assumed valid from other documentation.

---

## Fix Applied

Removed `--force`. Added separate task to delete placeholder TLS files before cert request, gated by same `when` condition.

---

## Lesson

Always verify CLI flags against the actual installed version. Never assume documentation flags apply to all versions.
