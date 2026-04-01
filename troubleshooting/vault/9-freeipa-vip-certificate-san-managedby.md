# Case 63: FreeIPA VIP Certificate SAN — Managedby Permissions for Multi-Host Certificates

**Component:** HashiCorp Vault | FreeIPA | Certmonger | Keepalived
**Date:** March 29, 2026

---

## Symptom

When adding a VIP hostname (`vault.lab.local`) as a second DNS SAN in FreeIPA-issued certificates for Vault cluster nodes, the certificate request was rejected:

```
status: CA_REJECTED
ca-error: Server at https://freeipa.lab.local/ipa/json denied our request, giving up:
2100 (Insufficient access: Insufficient privilege to create a certificate with subject alt name 'vault.lab.local'.).
stuck: yes
```

Individual node certificates worked (e.g., `vault1.lab.local`), but adding the VIP SAN failed.

---

## Context & Why This Was Needed

The goal was to add Keepalived VIP (`vault.lab.local → 10.0.62.100`) as a single HA entry point for the 3-node Vault cluster. The VIP DNS record was added to FreeIPA successfully. However, when K8s pods tried to connect via `https://vault.lab.local:8200`, TLS failed because the existing Vault certificates only contained `vault1.lab.local` (or vault2/vault3) as the SAN — not the VIP hostname.

The solution required reissuing all Vault node certs to include `vault.lab.local` as an additional DNS SAN alongside the node's own hostname.

---

## Error Evidence Trail

**Error 1 — Initial curl from K8s master:**
```
curl: (60) SSL: no alternative certificate subject name matches target hostname 'vault.lab.local'
```
→ Confirmed the cert SAN was missing the VIP hostname.

**Error 2 — After adding `-D vault.lab.local` to cert request:**
```
status: CA_UNREACHABLE
ca-error: 4001 (The service principal for subject alt name vault.lab.local in certificate request does not exist)
```
→ FreeIPA requires a service principal for every SAN. `vault/vault.lab.local` didn't exist.

**Error 3 — After adding VIP host + service principal, host managedby was wrong:**
```
status: CA_REJECTED
ca-error: 2100 (Insufficient access: Insufficient privilege to create a certificate with subject alt name 'vault.lab.local')
stuck: yes
```
→ Even with the service principal existing, the vault nodes had no permission to request certs for it. Both HOST and SERVICE managedby were needed.

**Error 4 — Wrong IPA command used:**
```
ipa: ERROR: unknown command 'service-add-managedby'
```
→ This command doesn't exist in this FreeIPA version. Had to use `ipa service-mod --addattr=managedby=...` instead.

**Error 5 — Comma-separated hosts syntax failed silently:**
```bash
# WRONG - accepted but only added vault1, vault2, vault3 as one invalid entry
ipa host-add-managedby vault.lab.local --hosts=vault1.lab.local,vault2.lab.local,vault3.lab.local
```
→ Must be separate calls per host.

**Error 6 — `-w` timeout on cert request (misleading failure):**
```
rc: 2 — "New signing request added" but Ansible reported FAILED
```
→ The `-w` flag waits for cert issuance. If IPA takes longer than expected, it times out and returns rc:2 even though the request was submitted. Not a real failure — check with `ipa-getcert list` to confirm actual status.

---

## Investigation Flow

### Step 1: Initial Playbook Configuration

The playbook attempted to request certificates with two DNS SANs:

```yaml
- name: Request signed certificate from FreeIPA
  ansible.builtin.command: >
    ipa-getcert request
    -w
    -f /opt/vault/tls/tls.crt
    -k /opt/vault/tls/tls.key
    -K vault/{{ inventory_hostname }}
    -N CN={{ inventory_hostname }}
    -D {{ inventory_hostname }}
    -D vault.lab.local        # <-- This caused the failure
    -C "systemctl reload vault"
```

### Step 2: Checking Existing Permissions

```bash
[root@freeipa ~]# ipa host-show vault.lab.local --all | grep -i "managed by"
  Managed by: vault.lab.local

[root@freeipa ~]# ipa service-show vault/vault.lab.local --all | grep -i "managed by"
  Managed by: vault.lab.local
```

**Finding:** Only self-managed. Individual vault nodes (vault1/2/3) were NOT listed as managers.

### Step 3: First Fix Attempt — Host Managedby (Partial)

The original playbook used comma-separated hosts (incorrect syntax):

```yaml
# WRONG - comma-separated doesn't work
ipa host-add-managedby vault.lab.local --hosts=vault1.lab.local,vault2.lab.local,vault3.lab.local
```

**Fix:** Separate calls for each host:

```yaml
ipa host-add-managedby vault.lab.local --hosts=vault1.lab.local
ipa host-add-managedby vault.lab.local --hosts=vault2.lab.local
ipa host-add-managedby vault.lab.local --hosts=vault3.lab.local
```

### Step 4: Second Issue — Service Managedby Command Missing

```bash
[root@freeipa ~]# ipa service-add-managedby vault/vault.lab.local --hosts=vault1.lab.local
ipa: ERROR: unknown command 'service-add-managedby'
```

**Root Cause:** The `service-add-managedby` command does not exist in this FreeIPA version.

**Fix:** Use `ipa service-mod --addattr` instead:

```bash
ipa service-mod vault/vault.lab.local --addattr=managedby=fqdn=vault1.lab.local,cn=computers,cn=accounts,dc=lab,dc=local
ipa service-mod vault/vault.lab.local --addattr=managedby=fqdn=vault2.lab.local,cn=computers,cn=accounts,dc=lab,dc=local
ipa service-mod vault/vault.lab.local --addattr=managedby=fqdn=vault3.lab.local,cn=computers,cn=accounts,dc=lab,dc=local
```

### Step 5: Verification After Fix

```bash
[root@freeipa ~]# ipa host-show vault.lab.local --all | grep -i "managed by"
  Managed by: vault.lab.local, vault1.lab.local, vault2.lab.local, vault3.lab.local

[root@freeipa ~]# ipa service-show vault/vault.lab.local --all | grep -i "managed by"
  Managed by: vault.lab.local, vault1.lab.local, vault2.lab.local, vault3.lab.local
```

### Step 6: Resubmit Certificate Requests

```bash
[root@ansible ~]# ssh vault1 "ipa-getcert resubmit -i 20260329180348 && sleep 2 && ipa-getcert list"
Resubmitting "20260329180348" to "IPA".
Number of certificates and requests being tracked: 1.
Request ID '20260329180348':
        status: MONITORING
        stuck: no
        ...
        dns: vault1.lab.local,vault.lab.local    # <-- SUCCESS: Both SANs present
        principal name: vault/vault1.lab.local@LAB.LOCAL
```

### Step 7: Final Verification

```bash
[root@ansible ~]# ssh vault1 "openssl x509 -in /opt/vault/tls/tls.crt -noout -text | grep -A2 'Subject Alternative'"
            X509v3 Subject Alternative Name:
                DNS:vault1.lab.local, DNS:vault.lab.local, othername: UPN:vault/vault1.lab.local@LAB.LOCAL

[root@ansible ~]# curl https://vault.lab.local:8200
<a href="/ui/">Temporary Redirect</a>.
```

---

## Root Cause Summary

1. **Syntax Error:** `ipa host-add-managedby --hosts=` doesn't accept comma-separated values
2. **Missing Command:** `ipa service-add-managedby` does not exist in FreeIPA; must use `ipa service-mod --addattr`
3. **Permission Model:** For a certificate to include a SAN for another host/VIP, both the HOST and SERVICE managedby relationships must be configured
4. **Task Ordering:** The `service-mod` task must run AFTER the service principals are created, otherwise the service doesn't exist yet and the managedby relationship is never added

---

## Fix Applied

Updated `ansible/dev/playbooks/vault/vault_setup.yml`:

**IMPORTANT:** Task order matters - service principals must be created BEFORE adding managedby relationships:

```yaml
# 1. First create the service principals
- name: Create Vault service principals in FreeIPA
  freeipa.ansible_freeipa.ipaservice:
    ipaadmin_principal: "{{ ipaadmin_principal }}"
    ipaadmin_password: "{{ ipaadmin_password }}"
    name: "vault/{{ item }}"
    state: present
  loop:
    - vault1.lab.local
    - vault2.lab.local
    - vault3.lab.local
    - vault.lab.local

# 2. Then add host managedby
- name: Add managedby relationship for Vault VIP
  ansible.builtin.shell: |
    echo "{{ ipaadmin_password }}" | kinit admin
    ipa host-add-managedby vault.lab.local --hosts=vault1.lab.local
    ipa host-add-managedby vault.lab.local --hosts=vault2.lab.local
    ipa host-add-managedby vault.lab.local --hosts=vault3.lab.local
    kdestroy
  failed_when: false
  no_log: true

# 3. Finally add service managedby (AFTER service exists!)
- name: Add service managedby for VIP service
  ansible.builtin.shell: |
    echo "{{ ipaadmin_password }}" | kinit admin
    ipa service-mod vault/vault.lab.local --addattr=managedby=fqdn=vault1.lab.local,cn=computers,cn=accounts,dc=lab,dc=local
    ipa service-mod vault/vault.lab.local --addattr=managedby=fqdn=vault2.lab.local,cn=computers,cn=accounts,dc=lab,dc=local
    ipa service-mod vault/vault.lab.local --addattr=managedby=fqdn=vault3.lab.local,cn=computers,cn=accounts,dc=lab,dc=local
    kdestroy
  failed_when: false
  no_log: true
```

---

## Lesson Learned

1. FreeIPA certificate SAN permissions require BOTH host AND service managedby relationships
2. Always verify IPA commands exist in your version before using them in automation
3. The `--addattr=managedby=fqdn=HOSTNAME,cn=computers,cn=accounts,dc=DOMAIN,dc=TLD` syntax is required for service managedby
4. Use separate calls for multiple hosts instead of comma-separated lists
5. **Task ordering is critical:** Service managedby must be added AFTER service principals are created - otherwise the service doesn't exist and the command silently fails (due to `failed_when: false`)

---

## Commands Reference

```bash
# Check host managedby relationships
ipa host-show vault.lab.local --all | grep -i "managed by"

# Check service managedby relationships
ipa service-show vault/vault.lab.local --all | grep -i "managed by"

# Add host managedby (one per host)
ipa host-add-managedby vault.lab.local --hosts=vault1.lab.local

# Add service managedby (using service-mod)
ipa service-mod vault/vault.lab.local --addattr=managedby=fqdn=vault1.lab.local,cn=computers,cn=accounts,dc=lab,dc=local

# Check certmonger request status
ipa-getcert list

# Resubmit failed certificate request
ipa-getcert resubmit -i REQUEST_ID

# Verify certificate SANs
openssl x509 -in /opt/vault/tls/tls.crt -noout -text | grep -A2 "Subject Alternative"
```

### Recovering from Stuck Certificate Requests

If certificate requests are stuck with `CA_REJECTED` status, use these ansible ad-hoc commands:

```bash
# 1. Stop tracking the stuck certificate on all vault nodes
ansible vault_cluster -i inventory/inventory.ini -m command -a "ipa-getcert stop-tracking -f /opt/vault/tls/tls.crt" -b

# 2. Remove old certificate files
ansible vault_cluster -i inventory/inventory.ini -m file -a "path=/opt/vault/tls/tls.crt state=absent" -b
ansible vault_cluster -i inventory/inventory.ini -m file -a "path=/opt/vault/tls/tls.key state=absent" -b

# 3. Re-run vault_setup.yml to request new certificates (with correct managedby)
ansible-playbook -i inventory/inventory.ini playbooks/vault/vault_setup.yml

# 4. Restart vault to load new certificates
ansible vault_cluster -i inventory/inventory.ini -m systemd -a "name=vault state=restarted" -b
```

---

## Related Cases

- Case 27: FreeIPA CA Rejected CSR — Hostname Mismatch
- Case 29: Vault TLS IP SAN Error
