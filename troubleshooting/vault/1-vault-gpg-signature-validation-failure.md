# Case 25: GPG Signature Validation Failure on Vault Install

**Component:** HashiCorp Vault | Rocky Linux LXC | Ansible
**Date:** March 17, 2026

---

## Symptom

DNF failed with:
```
Failed to validate GPG signature for vault-1.21.4-1.x86_64: Public key not installed
```

vault3 also threw `FileNotFoundError` on cached RPM.

---

## Root Cause

`yum_repository` module adds the GPG key URL to the repo file but does NOT import it into the RPM keystore. DNF requires the key physically imported via `rpm --import` before it can verify packages.

---

## Fix Applied

1. Added `ansible.builtin.rpm_key` task between repo and install tasks to import the HashiCorp GPG key into RPM
2. Ran `dnf clean all` on all nodes to clear corrupted cache

---

## Lesson

`yum_repository` and `rpm_key` are two separate steps on RHEL-family systems. Adding a repo URL is never sufficient — the key must also be imported into the RPM keystore.

---

## Commands

```bash
# Clean DNF cache after failed install
ansible vault_cluster -m command -a "dnf clean all" --become

# Check GPG key import
rpm -q gnupg2
rpm -qf /opt/vault/tls/tls.crt
rpm -q --scripts vault
```
