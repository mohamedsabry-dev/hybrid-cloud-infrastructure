# TS-IDN-003 | 2026-03-05 | RESOLVED

## 1. Context
- System: Kerberos / GSSAPI / SSH
- Environment: DEV (lab.local)
- Related components: All FreeIPA domain hosts, Ansible inventory

## 2. Issue
- Symptom: SSH works with hostnames but fails with IP addresses
- Error:
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

## 3. Analysis

**Check 1: How does Kerberos authentication work?**
```
1. Client requests ticket for: host/k8s-worker1.lab.local@LAB.LOCAL
2. KDC checks: Does this principal exist? Yes.
3. Client presents ticket to server
4. Server validates: Am I k8s-worker1.lab.local? Yes.
5. Authentication succeeds
```

**Check 2: What happens with IP addresses?**
```
1. Client requests ticket for: host/10.0.64.11@LAB.LOCAL
2. KDC checks: Does this principal exist? NO!
3. Authentication fails
```

The service principal is `host/FQDN@REALM`, not `host/IP@REALM`.

## 4. Root Cause
> Kerberos service principals are tied to **hostnames**, not IP addresses. The principal format is `host/FQDN@REALM` (e.g., `host/k8s-worker1.lab.local@LAB.LOCAL`). There is no `host/10.0.64.11@LAB.LOCAL` principal registered.

**Simple analogy:** Kerberos is like a VIP guest list - list says "Allow John Smith from Acme Corp", not "Allow person from 123 Main Street". Must identify by name, not address.

## 5. Solution
> Use FQDNs (Fully Qualified Domain Names) in Ansible inventory instead of IPs.

**Why this works:** When SSH connects to `k8s-worker1.lab.local`, Kerberos can find the matching principal. When connecting to an IP, there's no matching principal.

**File:** `ansible/dev/inventory/inventory.ini`

**Location:** Ansible control node inventory configuration

**Before (broken):**
```ini
[k8s_workers]
k8s-worker1.lab.local ansible_host=10.0.64.10
k8s-worker2.lab.local ansible_host=10.0.64.11
k8s-worker3.lab.local ansible_host=10.0.64.12
```

**After (working):**
```ini
[k8s_workers]
k8s-worker1.lab.local
k8s-worker2.lab.local
k8s-worker3.lab.local
```

FreeIPA provides DNS resolution, so hostnames resolve correctly without specifying `ansible_host`.

**Prerequisites:**
1. FreeIPA DNS must be working - clients should use FreeIPA as DNS server
2. Kerberos ticket must exist - run `kinit username` before SSH/Ansible

**Verification:**
```bash
# Check DNS resolution
dig k8s-worker1.lab.local

# Check Kerberos ticket
klist

# Verbose SSH to see GSSAPI
ssh -v super_bot@k8s-worker1.lab.local 2>&1 | grep -i gssapi
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact: None - just using proper hostnames instead of IPs

## 7. Impact After Fix
- Observed: All GSSAPI authentication works with FQDNs
- No new issues caused

## 8. Notes

**If you MUST use IPs:**

1. Disable GSSAPI and use password auth:
   ```bash
   ssh -o GSSAPIAuthentication=no super_bot@10.0.64.11
   ```

2. Add IP to /etc/hosts on the client with the hostname:
   ```
   10.0.64.11 k8s-worker1.lab.local k8s-worker1
   ```

3. Use password authentication instead of Kerberos (less secure)

## 9. Workaround (if any)
> 1. `ssh -o GSSAPIAuthentication=no user@IP` to bypass Kerberos and use password auth.
> 2. `ssh root@IP` - all nodes have ansible public key trusted (injected during infra init phase via GitHub workflow), so root SSH with key works regardless of Kerberos.
