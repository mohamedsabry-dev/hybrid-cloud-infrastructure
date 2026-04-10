# TS-VLT-002 | 2026-03-29 | RESOLVED

## 1. Context
- System: FreeIPA / Certmonger / TLS Certificates
- Environment: Vault HA cluster with Keepalived VIP
- Related components: vault1/2/3.lab.local, VIP vault.lab.local (10.0.62.100), FreeIPA CA
- Related tickets: [TS-VLT-001](1-vault-cluster-initial-setup-investigation.md) - Initial Vault setup

## 2. Issue
- Symptom: Certificate request rejected when adding VIP hostname as additional SAN
- Error:
```
status: CA_REJECTED
ca-error: Server at https://freeipa.lab.local/ipa/json denied our request, giving up:
2100 (Insufficient access: Insufficient privilege to create a certificate with subject alt name 'vault.lab.local'.).
stuck: yes
```

**Goal:** Add Keepalived VIP (`vault.lab.local → 10.0.62.100`) as single HA entry point. K8s pods connecting via `https://vault.lab.local:8200` failed TLS because existing certs only contained individual node hostnames.

## 3. Analysis

**Error Trail - 6 distinct errors encountered during investigation:**

---

**Error 1: Initial TLS failure from K8s**
```bash
curl https://vault.lab.local:8200
# curl: (60) SSL: no alternative certificate subject name matches target hostname 'vault.lab.local'
```
Finding: Certificate SAN missing VIP hostname. ✓

---

**Error 2: After adding `-D vault.lab.local` to cert request**
```
status: CA_UNREACHABLE
ca-error: 4001 (The service principal for subject alt name vault.lab.local in certificate request does not exist)
```
Finding: FreeIPA requires service principal for every SAN. `vault/vault.lab.local` didn't exist. ✓

---

**Error 3: After adding VIP host + service principal**
```
status: CA_REJECTED
ca-error: 2100 (Insufficient access: Insufficient privilege to create a certificate with subject alt name 'vault.lab.local')
stuck: yes
```
Finding: Service principal exists but vault nodes don't have permission to request certs for it. ✓

---

**Error 4: Wrong IPA command**
```bash
ipa service-add-managedby vault/vault.lab.local --hosts=vault1.lab.local
# ipa: ERROR: unknown command 'service-add-managedby'
```
Finding: Command doesn't exist in this FreeIPA version. ✓

---

**Error 5: Comma-separated hosts syntax**
```bash
# WRONG - accepted but created one invalid entry
ipa host-add-managedby vault.lab.local --hosts=vault1.lab.local,vault2.lab.local,vault3.lab.local
```
Finding: Must use separate calls per host. ✓

---

**Error 6: `-w` timeout misleading failure**
```
rc: 2 — "New signing request added" but Ansible reported FAILED
```
Finding: `-w` flag waits for issuance. If IPA takes longer, rc:2 returned even though request submitted. Check `ipa-getcert list` for actual status. ✓

---

**Check 1: Initial playbook configuration**
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

---

**Check 2: Existing permissions**
```bash
[root@freeipa ~]# ipa host-show vault.lab.local --all | grep -i "managed by"
  Managed by: vault.lab.local

[root@freeipa ~]# ipa service-show vault/vault.lab.local --all | grep -i "managed by"
  Managed by: vault.lab.local
```
Finding: Only self-managed. vault1/2/3 NOT listed as managers. ✓

---

**Check 3: Fix attempt - host managedby (partial)**
```bash
# WRONG - comma-separated doesn't work
ipa host-add-managedby vault.lab.local --hosts=vault1.lab.local,vault2.lab.local,vault3.lab.local

# CORRECT - separate calls
ipa host-add-managedby vault.lab.local --hosts=vault1.lab.local
ipa host-add-managedby vault.lab.local --hosts=vault2.lab.local
ipa host-add-managedby vault.lab.local --hosts=vault3.lab.local
```

---

**Check 4: Service managedby - command discovery**
```bash
# This command doesn't exist
ipa service-add-managedby vault/vault.lab.local --hosts=vault1.lab.local

# Must use service-mod --addattr instead
ipa service-mod vault/vault.lab.local --addattr=managedby=fqdn=vault1.lab.local,cn=computers,cn=accounts,dc=lab,dc=local
```

---

**Check 5: Verification after fix**
```bash
[root@freeipa ~]# ipa host-show vault.lab.local --all | grep -i "managed by"
  Managed by: vault.lab.local, vault1.lab.local, vault2.lab.local, vault3.lab.local

[root@freeipa ~]# ipa service-show vault/vault.lab.local --all | grep -i "managed by"
  Managed by: vault.lab.local, vault1.lab.local, vault2.lab.local, vault3.lab.local
```
Finding: All nodes now have managedby permissions. ✓

---

**Check 6: Resubmit certificate request**
```bash
[root@ansible ~]# ssh vault1 "ipa-getcert resubmit -i 20260329180348 && sleep 2 && ipa-getcert list"
Resubmitting "20260329180348" to "IPA".
Request ID '20260329180348':
        status: MONITORING
        stuck: no
        dns: vault1.lab.local,vault.lab.local    # <-- SUCCESS: Both SANs present
```

---

**Check 7: Final verification**
```bash
[root@ansible ~]# ssh vault1 "openssl x509 -in /opt/vault/tls/tls.crt -noout -text | grep -A2 'Subject Alternative'"
            X509v3 Subject Alternative Name:
                DNS:vault1.lab.local, DNS:vault.lab.local, othername: UPN:vault/vault1.lab.local@LAB.LOCAL

[root@ansible ~]# curl https://vault.lab.local:8200
<a href="/ui/">Temporary Redirect</a>.
```
Finding: Certificate has both SANs, TLS works via VIP. ✓

## 4. Root Cause
> For a certificate to include a SAN for another host/VIP, FreeIPA requires **BOTH** host AND service managedby relationships configured. Additionally:
> 1. `ipa host-add-managedby --hosts=` doesn't accept comma-separated values
> 2. `ipa service-add-managedby` doesn't exist - must use `ipa service-mod --addattr`
> 3. Task ordering critical: service principals must exist BEFORE adding managedby

## 5. Solution
> Configure both HOST and SERVICE managedby relationships allowing vault nodes to request certs with VIP SAN.

**File:** `ansible/dev/playbooks/vault/vault_setup.yml`

**Task order matters:**
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

## 6. Solution Risk
- Risk level: LOW
- Potential impact: None - just permission configuration for certificate requests

## 7. Impact After Fix
- Observed: All vault nodes have certificates with both individual hostname AND VIP SAN
- K8s pods can connect via `https://vault.lab.local:8200`
- No new issues caused

## 8. Notes

**Key Lessons:**
1. FreeIPA certificate SAN permissions require BOTH host AND service managedby relationships
2. Always verify IPA commands exist in your version before using in automation
3. `--addattr=managedby=fqdn=HOSTNAME,cn=computers,cn=accounts,dc=DOMAIN,dc=TLD` syntax required for service managedby
4. Use separate calls for multiple hosts instead of comma-separated lists
5. Task ordering critical: service managedby must be added AFTER service principals created

**Commands Reference:**
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

**Recovering from Stuck Certificate Requests:**
```bash
# 1. Stop tracking the stuck certificate on all vault nodes
ansible vault_cluster -m command -a "ipa-getcert stop-tracking -f /opt/vault/tls/tls.crt" -b

# 2. Remove old certificate files
ansible vault_cluster -m file -a "path=/opt/vault/tls/tls.crt state=absent" -b
ansible vault_cluster -m file -a "path=/opt/vault/tls/tls.key state=absent" -b

# 3. Re-run vault_setup.yml to request new certificates
ansible-playbook playbooks/vault/vault_setup.yml

# 4. Restart vault to load new certificates
ansible vault_cluster -m systemd -a "name=vault state=restarted" -b
```

## 9. Workaround (if any)
> Use `tls-skip-verify` temporarily (NOT recommended for production).

