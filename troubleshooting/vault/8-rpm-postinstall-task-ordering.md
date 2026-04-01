# Case 32: Task Ordering — RPM Post-Install Running Before Ansible Tasks

**Component:** Ansible | RPM | HashiCorp Vault
**Date:** March 17, 2026

---

## Symptom

Vault RPM post-install script created `/opt/vault/tls`, `/opt/vault/data`, vault user, and self-signed TLS certs before Ansible directory and user tasks ran.

---

## Root Cause

Directory and user creation tasks were placed after `dnf install vault` in the playbook. RPM post-install script runs synchronously as part of install — before Ansible continues to the next task.

---

## Fix Applied

Tasks kept for explicit state enforcement and idempotency. Noted as known ordering issue — correct fix is to reorder: create user/dirs BEFORE install task.

---

## Lesson

RPM post-install scripts run synchronously during `dnf install`. Any Ansible tasks that should own resource creation must come BEFORE the install task, not after.
