# TS-VLT-002 | 2026-03-29 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Vault / Identity
Sub-techs: FreeIPA CA, Certmonger, ipa-getcert, TLS certificates, Keepalived VIP,
           managedby relationships, Ansible
Environment: DEV lab.local | Vault HA cluster | vault1/2/3.lab.local |
             VIP vault.lab.local (10.0.62.100) | FreeIPA CA
Re-opened: No

_____________________________________________________________________

[Issue Description]
Certificate request rejected when adding VIP hostname (vault.lab.local) as an
additional SAN. K8s pods connecting via https://vault.lab.local:8200 failed TLS
because existing certs only contained individual node hostnames.

  curl https://vault.lab.local:8200
  curl: (60) SSL: no alternative certificate subject name matches target hostname 'vault.lab.local'

Goal: add Keepalived VIP vault.lab.local as single HA entry point with TLS coverage.

Related ticket: TS-VLT-001 — initial Vault cluster setup

_____________________________________________________________________

[Analysis]

# Initial Check Notes:

6 distinct errors encountered in sequence during investigation:

Error 1 — Initial TLS failure from K8s:
  curl https://vault.lab.local:8200
  SSL: no alternative certificate subject name matches target hostname 'vault.lab.local'
  Finding: certificate SAN missing VIP hostname.

Error 2 — After adding -D vault.lab.local to cert request:
  status: CA_UNREACHABLE
  ca-error: 4001 (The service principal for subject alt name vault.lab.local
  in certificate request does not exist)
  Finding: FreeIPA requires a service principal for every SAN.
  vault/vault.lab.local did not exist yet.

Error 3 — After adding VIP host and service principal:
  status: CA_REJECTED
  ca-error: 2100 (Insufficient access: Insufficient privilege to create a
  certificate with subject alt name 'vault.lab.local')
  stuck: yes
  Finding: service principal exists but vault nodes have no permission to
  request certs for it.

Error 4 — Wrong IPA command for service managedby:
  ipa service-add-managedby vault/vault.lab.local --hosts=vault1.lab.local
  ipa: ERROR: unknown command 'service-add-managedby'
  Finding: command does not exist in this FreeIPA version.

Error 5 — Comma-separated hosts syntax:
  ipa host-add-managedby vault.lab.local --hosts=vault1.lab.local,vault2.lab.local,vault3.lab.local
  Accepted but created one invalid entry.
  Finding: must use separate calls per host.

Error 6 — -w timeout misleading failure:
  rc: 2 — "New signing request added" but Ansible reported FAILED.
  Finding: -w flag waits for issuance. If IPA takes longer than timeout,
  rc:2 returned even though request was submitted. Check ipa-getcert list
  for actual status — do not trust rc alone.

Check 1 — Initial playbook configuration that caused failures:
  ipa-getcert request
    -K vault/{{ inventory_hostname }}
    -N CN={{ inventory_hostname }}
    -D {{ inventory_hostname }}
    -D vault.lab.local        ← this triggered the permission errors
    -f /opt/vault/tls/tls.crt
    -k /opt/vault/tls/tls.key

Check 2 — Existing managedby permissions on FreeIPA:
  Command:
    ipa host-show vault.lab.local --all | grep -i "managed by"
    ipa service-show vault/vault.lab.local --all | grep -i "managed by"
  Output:
    Managed by: vault.lab.local   (self only)
    vault1/2/3 NOT listed as managers.

  For vault nodes to request a cert with vault.lab.local as SAN, they need
  BOTH host AND service managedby relationships on the VIP.

Check 3 — Adding host managedby (correct syntax):
  WRONG — comma-separated does not work:
    ipa host-add-managedby vault.lab.local --hosts=vault1.lab.local,vault2.lab.local,vault3.lab.local

  CORRECT — separate calls required:
    ipa host-add-managedby vault.lab.local --hosts=vault1.lab.local
    ipa host-add-managedby vault.lab.local --hosts=vault2.lab.local
    ipa host-add-managedby vault.lab.local --hosts=vault3.lab.local

Check 4 — Adding service managedby (correct command):
  ipa service-add-managedby does not exist.
  Must use service-mod --addattr:
    ipa service-mod vault/vault.lab.local \
      --addattr=managedby=fqdn=vault1.lab.local,cn=computers,cn=accounts,dc=lab,dc=local
    ipa service-mod vault/vault.lab.local \
      --addattr=managedby=fqdn=vault2.lab.local,cn=computers,cn=accounts,dc=lab,dc=local
    ipa service-mod vault/vault.lab.local \
      --addattr=managedby=fqdn=vault3.lab.local,cn=computers,cn=accounts,dc=lab,dc=local

Check 5 — Verification after adding both relationships:
  ipa host-show vault.lab.local --all | grep -i "managed by"
  Output: Managed by: vault.lab.local, vault1.lab.local, vault2.lab.local, vault3.lab.local

  ipa service-show vault/vault.lab.local --all | grep -i "managed by"
  Output: Managed by: vault.lab.local, vault1.lab.local, vault2.lab.local, vault3.lab.local

Check 6 — Resubmit and verify:
  ssh vault1 "ipa-getcert resubmit -i 20260329180348 && sleep 2 && ipa-getcert list"
  Output:
    status: MONITORING
    stuck: no
    dns: vault1.lab.local,vault.lab.local   ← both SANs present

  openssl x509 -in /opt/vault/tls/tls.crt -noout -text | grep -A2 "Subject Alternative"
  Output:
    X509v3 Subject Alternative Name:
      DNS:vault1.lab.local, DNS:vault.lab.local, othername: UPN:vault/vault1.lab.local@LAB.LOCAL

  curl https://vault.lab.local:8200
  Output: <a href="/ui/">Temporary Redirect</a>. ← TLS working via VIP


# Suspected Root Cause
FreeIPA requires BOTH host AND service managedby relationships for a node to
request a certificate containing a SAN for another host/VIP. Neither relationship
alone is sufficient. Additionally, service managedby must be added AFTER the
service principal exists, and must use service-mod --addattr syntax (not a
dedicated command that does not exist).


# More Checks Notes:
Task ordering is critical:
  1. Create service principals first (vault/vault.lab.local must exist)
  2. Add host managedby (separate call per host)
  3. Add service managedby AFTER service principal exists


# Suspected Solution
Configure both host and service managedby relationships via Ansible playbook
in correct order, then resubmit certificate requests.


# Test
Added both managedby relationships, resubmitted cert request on vault1.

Result: PASS — status MONITORING, dns shows vault1.lab.local and vault.lab.local,
TLS working via vault.lab.local:8200.

_____________________________________________________________________

[Final Root Cause]
FreeIPA certificate SAN permissions require BOTH host AND service managedby
relationships to be configured. vault nodes (vault1/2/3) only had self-managed
relationships — no permission to request certs containing vault.lab.local as SAN.
Additionally: ipa service-add-managedby does not exist in this FreeIPA version,
ipa host-add-managedby does not accept comma-separated hosts, and service managedby
must be added after the service principal exists.

_____________________________________________________________________

[Final Solution]
Configured both host and service managedby relationships in correct task order.

Playbook: ansible/dev/playbooks/vault/vault_setup.yml

Step 1 — Create service principals first:
  freeipa.ansible_freeipa.ipaservice:
    name: "vault/{{ item }}"
    state: present
  loop:
    - vault1.lab.local
    - vault2.lab.local
    - vault3.lab.local
    - vault.lab.local

Step 2 — Add host managedby (one call per host):
  echo "{{ ipaadmin_password }}" | kinit admin
  ipa host-add-managedby vault.lab.local --hosts=vault1.lab.local
  ipa host-add-managedby vault.lab.local --hosts=vault2.lab.local
  ipa host-add-managedby vault.lab.local --hosts=vault3.lab.local
  kdestroy

Step 3 — Add service managedby AFTER service principal exists:
  echo "{{ ipaadmin_password }}" | kinit admin
  ipa service-mod vault/vault.lab.local \
    --addattr=managedby=fqdn=vault1.lab.local,cn=computers,cn=accounts,dc=lab,dc=local
  ipa service-mod vault/vault.lab.local \
    --addattr=managedby=fqdn=vault2.lab.local,cn=computers,cn=accounts,dc=lab,dc=local
  ipa service-mod vault/vault.lab.local \
    --addattr=managedby=fqdn=vault3.lab.local,cn=computers,cn=accounts,dc=lab,dc=local
  kdestroy

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Permission configuration only — no impact on existing infrastructure.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Key lessons:
  1. FreeIPA cert SAN permissions require BOTH host AND service managedby
  2. ipa service-add-managedby does not exist — use service-mod --addattr
  3. ipa host-add-managedby does not accept comma-separated — separate calls per host
  4. Task ordering: service principals must exist BEFORE adding service managedby
  5. -w flag on ipa-getcert can return rc:2 even on success — check ipa-getcert list
  6. Always verify IPA commands exist in your version before using in automation

Commands reference:
  ipa host-show vault.lab.local --all | grep -i "managed by"
  ipa service-show vault/vault.lab.local --all | grep -i "managed by"
  ipa host-add-managedby vault.lab.local --hosts=vault1.lab.local
  ipa service-mod vault/vault.lab.local \
    --addattr=managedby=fqdn=vault1.lab.local,cn=computers,cn=accounts,dc=lab,dc=local
  ipa-getcert list
  ipa-getcert resubmit -i REQUEST_ID
  openssl x509 -in /opt/vault/tls/tls.crt -noout -text | grep -A2 "Subject Alternative"

Recovering from stuck certificate requests:
  # Stop tracking on all vault nodes
  ansible vault_cluster -m command -a "ipa-getcert stop-tracking -f /opt/vault/tls/tls.crt" -b

  # Remove old files
  ansible vault_cluster -m file -a "path=/opt/vault/tls/tls.crt state=absent" -b
  ansible vault_cluster -m file -a "path=/opt/vault/tls/tls.key state=absent" -b

  # Re-run playbook to request new certificates
  ansible-playbook playbooks/vault/vault_setup.yml

  # Restart vault to load new certificates
  ansible vault_cluster -m systemd -a "name=vault state=restarted" -b