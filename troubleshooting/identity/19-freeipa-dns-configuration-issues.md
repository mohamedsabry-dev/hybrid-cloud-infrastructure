# TS-003: FreeIPA DNS Configuration Issues

**Date:** 2026-03-05
**Environment:** DEV (lab.local)
**Affected Systems:** FreeIPA server, all domain clients
**Status:** RESOLVED

---

## Issue 1: DNS Recursion Denied for Clients

### Symptom

Clients joined to FreeIPA domain cannot resolve external domains.

```bash
# From client - external DNS fails
dig @10.0.60.10 google.com
# status: REFUSED, WARNING: recursion requested but not available
# EDE: 18 (Prohibited)

# From FreeIPA server itself - works fine
dig google.com
# Returns valid response
```

### Root Cause

Two problems:

1. **Forwarders not applied:** Despite setting `ipaserver_forwarders` in the playbook, `ipa dnsconfig-show` showed empty configuration
2. **Recursion denied:** BIND defaults to allowing recursion only from localhost (127.0.0.1)

### Solution

Add post_tasks to `freeipa_setup.yml`:

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

**Important:** Use `/etc/named/ipa-options-ext.conf` (included inside BIND options block), NOT `/etc/named/ipa-ext.conf` which is outside the options context.

---

## Issue 2: DNS Forwarders Dictionary Syntax Error

### Symptom

```
TASK [Configure DNS forwarders]
fatal: [freeipa.lab.local]: FAILED! => "msg": "dictionary requested, could not parse JSON or key=value"
```

### Root Cause

The `freeipa.ansible_freeipa.ipadnsconfig` module expects forwarders as a list of dictionaries with `ip_address` keys, not plain strings.

### Solution

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

## Simple Explanation

### Why Recursion Failed

When a client asks FreeIPA's DNS server "What's the IP of google.com?":

1. FreeIPA DNS doesn't know google.com directly
2. It needs to ask upstream DNS servers (forwarders) - this is "recursion"
3. By default, BIND only allows recursion from 127.0.0.1 (itself)
4. Clients (10.0.x.x) get "REFUSED"

The fix tells BIND: "Allow clients from 10.0.0.0/8 to request recursive lookups."

### Why Forwarders Need Dictionary Format

The ansible-freeipa module was designed to accept additional forwarder options (like port numbers). So it expects:

```yaml
forwarders:
  - ip_address: 8.8.8.8
    port: 53           # optional
  - ip_address: 1.1.1.1
```

Even if you only specify IP, you must use the dictionary format.

---

## Verification

```bash
# Test from client
dig @10.0.60.10 google.com

# Check forwarders are set
ipa dnsconfig-show

# Check BIND config
cat /etc/named/ipa-options-ext.conf
```

---

## References

- [FreeIPA DNS Configuration](https://freeipa.readthedocs.io/en/latest/designs/dns.html)
- [BIND allow-recursion](https://bind9.readthedocs.io/en/latest/reference.html)
