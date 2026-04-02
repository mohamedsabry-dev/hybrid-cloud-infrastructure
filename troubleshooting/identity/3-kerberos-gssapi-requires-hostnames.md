# Case 3: Kerberos/GSSAPI Authentication Requires Hostnames

**Date:** 2026-03-05
**Environment:** DEV (lab.local)
**Affected Systems:** All FreeIPA domain hosts
**Status:** RESOLVED

---

## Symptom

SSH works with hostnames but fails with IP addresses.

```bash
# Using IP - FAILS
ssh super_bot@10.0.64.11
super_bot@10.0.64.11: Permission denied (publickey,gssapi-keyex,gssapi-with-mic,password)

# Using hostname - WORKS
ssh super_bot@k8s-worker1.lab.local
[super_bot@k8s-worker1 ~]$
```

Same with Ansible:

```bash
# Inventory with IPs - FAILS
ansible all -m ping
# Permission denied errors

# Inventory with FQDNs - WORKS
ansible all -m ping
# All green
```

---

## Root Cause

Kerberos authentication validates **service principals** which are tied to hostnames, not IP addresses.

### How Kerberos Authentication Works

```
1. Client requests ticket for: host/k8s-worker1.lab.local@LAB.LOCAL
2. KDC checks: Does this principal exist? Yes.
3. Client presents ticket to server
4. Server validates: Am I k8s-worker1.lab.local? Yes.
5. Authentication succeeds
```

### What Happens with IP Addresses

```
1. Client requests ticket for: host/10.0.64.11@LAB.LOCAL
2. KDC checks: Does this principal exist? NO!
3. Authentication fails
```

The service principal is `host/FQDN@REALM`, not `host/IP@REALM`.

---

## Solution

Use FQDNs (Fully Qualified Domain Names) in your Ansible inventory.

### Before (Broken)

```ini
[k8s_workers]
k8s-worker1.lab.local ansible_host=10.0.64.10
k8s-worker2.lab.local ansible_host=10.0.64.11
k8s-worker3.lab.local ansible_host=10.0.64.12
```

### After (Working)

```ini
[k8s_workers]
k8s-worker1.lab.local
k8s-worker2.lab.local
k8s-worker3.lab.local
```

FreeIPA provides DNS resolution, so hostnames resolve correctly.

---

## Prerequisites

1. **FreeIPA DNS must be working** - clients should use FreeIPA as DNS server
2. **Kerberos ticket must exist** - run `kinit username` before SSH/Ansible

```bash
# Get Kerberos ticket
kinit super_bot

# Verify ticket
klist

# Now SSH/Ansible will use GSSAPI
ssh super_bot@k8s-worker1.lab.local
ansible managed_hosts -m ping
```

---

## Simple Explanation

Kerberos is like a VIP guest list at a venue:

- Guest list says: "Allow **John Smith** from **Acme Corp**"
- You show up saying: "I'm the person from **123 Main Street**"
- Bouncer: "Sorry, I don't have **123 Main Street** on my list"

The list uses **names** (hostnames), not **addresses** (IPs). You must identify yourself by name.

---

## When You Must Use IPs

If you absolutely need to use IP addresses:

1. **Disable GSSAPI** and use password auth:
   ```bash
   ssh -o GSSAPIAuthentication=no super_bot@10.0.64.11
   ```

2. **Add IP to /etc/hosts** on the client with the hostname:
   ```
   10.0.64.11 k8s-worker1.lab.local k8s-worker1
   ```

3. **Use password authentication** instead of Kerberos (less secure)

---

## Verification

```bash
# Check DNS resolution
dig k8s-worker1.lab.local

# Check Kerberos ticket
klist

# Verbose SSH to see GSSAPI
ssh -v super_bot@k8s-worker1.lab.local 2>&1 | grep -i gssapi
```

---

## References

- [Kerberos Service Principals](https://web.mit.edu/kerberos/krb5-latest/doc/admin/princ_dns.html)
- [FreeIPA DNS Integration](https://freeipa.readthedocs.io/en/latest/designs/dns.html)
