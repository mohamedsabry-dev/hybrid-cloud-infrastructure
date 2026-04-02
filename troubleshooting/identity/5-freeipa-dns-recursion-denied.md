# Case 5: FreeIPA DNS Recursion Denied for Clients

**Component:** FreeIPA | BIND DNS
**Date:** March 2026

---

## Symptom

Clients cannot resolve external domains (e.g., `mirrors.fedoraproject.org`):

```bash
# From client - external DNS fails
dig @10.0.60.10 google.com
# status: REFUSED, WARNING: recursion requested but not available
# EDE: 18 (Prohibited)

# From FreeIPA server itself - works (queries from 127.0.0.1)
dig google.com
# works fine
```

---

## Root Cause

Two issues with ansible-freeipa role:

1. **Forwarders not applied**: Despite setting `ipaserver_forwarders` in playbook, `ipa dnsconfig-show` showed empty configuration
2. **Recursion denied**: BIND defaults to allowing recursion only from localhost (127.0.0.1)

---

## Fix Applied

Added to `freeipa_setup.yml` post_tasks:

```yaml
post_tasks:
  - name: Configure DNS forwarders
    freeipa.ansible_freeipa.ipadnsconfig:
      ipaadmin_password: "{{ ipaadmin_password }}"
      forwarders:
        - ip_address: 8.8.8.8
        - ip_address: 1.1.1.1
      forward_policy: first
      allow_sync_ptr: yes

  - name: Allow DNS recursion from internal networks
    ansible.builtin.blockinfile:
      path: /etc/named/ipa-options-ext.conf
      block: |
        allow-recursion { 127.0.0.1; 10.0.0.0/8; };
        allow-query-cache { 127.0.0.1; 10.0.0.0/8; };
      marker: "# {mark} ANSIBLE MANAGED - DNS RECURSION"
```

---

## Lesson

**Important:** Use `/etc/named/ipa-options-ext.conf` (included inside BIND options block), NOT `/etc/named/ipa-ext.conf` which is outside the options context.

---

## Verification

```bash
# Check forwarders
ipa dnsconfig-show

# Test recursion from client
dig @10.0.60.10 google.com
# Should return A record
```
