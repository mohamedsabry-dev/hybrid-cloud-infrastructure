# Case 34: FreeIPA DNS Forwarders Dictionary Syntax Error

**Component:** FreeIPA | ansible-freeipa | ipadnsconfig
**Date:** March 2026

---

## Symptom

```
TASK [Configure DNS forwarders]
fatal: [freeipa.lab.local]: FAILED! => "msg": "dictionary requested, could not parse JSON or key=value"
```

---

## Root Cause

The `freeipa.ansible_freeipa.ipadnsconfig` module expects forwarders as a list of dictionaries with `ip_address` keys, not plain strings.

---

## Fix Applied

**Wrong:**
```yaml
forwarders:
  - 8.8.8.8
  - 1.1.1.1
```

**Correct:**
```yaml
forwarders:
  - ip_address: 8.8.8.8
  - ip_address: 1.1.1.1
```

---

## Lesson

Always check ansible-freeipa module documentation for exact parameter format. The module parameters don't always match the IPA CLI syntax.
