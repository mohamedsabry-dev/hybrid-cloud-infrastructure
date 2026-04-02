# Case 6: $(hostname -f) Expanding on Control Node Instead of Remote

**Component:** Ansible | Shell
**Date:** March 17, 2026

---

## Symptom

All vault nodes tried to connect to `ansible.lab.local:8200` instead of their own hostname.

---

## Root Cause

Double quotes allowed the Ansible control node shell to expand `$(hostname -f)` before the command was sent remotely.

---

## Fix Applied

Escaped with backslash: `\$(hostname -f)` to force expansion on the remote node.

---

## Lesson

Use `\$` to escape variables that should expand on the remote node, not the Ansible control node.
