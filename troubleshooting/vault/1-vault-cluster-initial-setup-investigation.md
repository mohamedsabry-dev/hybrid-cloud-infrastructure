# TS-VLT-001 | 2026-03-17 | RESOLVED

## 1. Context
- System: HashiCorp Vault / FreeIPA CA / Certmonger / Ansible
- Environment: 3-node Vault cluster on Rocky Linux 10 LXC containers (vault1, vault2, vault3)
- Related components: DNF/RPM, ipa-getcert, TLS certificates, systemd

## 2. Issue
- Symptom: Multiple failures during initial Vault cluster deployment
- Error: Series of issues encountered during installation, certificate provisioning, and configuration
- This document covers the full installation journey with all issues encountered and resolved on the same day.

---

# PHASE 1: GPG Signature Validation Failure | 2026-03-17

## Symptoms (Phase 1)
DNF failed during Vault package installation:
```
Failed to validate GPG signature for vault-1.21.4-1.x86_64: Public key not installed
```

Additional error on vault3: `FileNotFoundError` on cached RPM.

---

## 3. Analysis (Phase 1)

**Check 1: RPM GPG keystore**
```bash
rpm -q gpg-pubkey --qf '%{NAME}-%{VERSION}-%{RELEASE}\t%{SUMMARY}\n'
```
Finding: HashiCorp GPG key not present in RPM keystore.

**Check 2: Ansible playbook review**
```yaml
# Current implementation
- name: Add HashiCorp repo
  yum_repository:
    name: hashicorp
    baseurl: https://rpm.releases.hashicorp.com/RHEL/$releasever/$basearch/stable
    gpgkey: https://rpm.releases.hashicorp.com/gpg
```
Finding: `yum_repository` adds GPG key URL to repo file but does NOT import it into RPM keystore.

---

## 4. Root Cause (Phase 1)
> `yum_repository` module only adds the GPG key URL to the repo file but does NOT import it into the RPM keystore. DNF requires the key physically imported via `rpm --import` before it can verify signed packages.

---

## 5. Solution (Phase 1)

**Step 1: Clean corrupted cache**
```bash
ansible vault_cluster -m command -a "dnf clean all" --become
```

**Step 2: Add rpm_key task to playbook**
```yaml
- name: Add HashiCorp repo
  yum_repository:
    name: hashicorp
    baseurl: https://rpm.releases.hashicorp.com/RHEL/$releasever/$basearch/stable
    gpgkey: https://rpm.releases.hashicorp.com/gpg

- name: Import HashiCorp GPG key
  ansible.builtin.rpm_key:
    key: https://rpm.releases.hashicorp.com/gpg
    state: present

- name: Install Vault
  ansible.builtin.dnf:
    name: vault
    state: present
```

**Lesson:** On RHEL-family systems, `yum_repository` and `rpm_key` are two separate steps.

---
---

# PHASE 2: Certmonger --force Flag Not Recognized | 2026-03-17

## Symptoms (Phase 2)
`ipa-getcert request` failed on all 3 nodes:
```
unrecognized option --force
```

---

## 3. Analysis (Phase 2)

**Check 1: Certmonger version**
```bash
rpm -q certmonger
# certmonger-0.79.20-3.el10
```
Finding: Rocky Linux 10 ships certmonger 0.79.20-3.

**Check 2: ipa-getcert help**
```bash
ipa-getcert request --help
```
Finding: `--force` flag does not exist in this version.

---

## 4. Root Cause (Phase 2)
> `--force` flag does not exist in certmonger 0.79.20-3.el10 installed on Rocky Linux 10. Flag was incorrectly assumed valid from other documentation or older versions.

---

## 5. Solution (Phase 2)

**Remove `--force` flag and add separate cleanup task:**
```yaml
- name: Remove placeholder TLS files if exist
  file:
    path: "{{ item }}"
    state: absent
  loop:
    - /opt/vault/tls/tls.crt
    - /opt/vault/tls/tls.key
  when: vault_cert_needed | default(false)

- name: Request certificate
  command: >
    ipa-getcert request
    -f /opt/vault/tls/tls.crt
    -k /opt/vault/tls/tls.key
    ...
  when: vault_cert_needed | default(false)
```

**Lesson:** Always verify CLI flags against the actual installed version.

---
---

# PHASE 3: FreeIPA CA Rejected CSR — Hostname Mismatch | 2026-03-17

## Symptoms (Phase 3)
Certificate request rejected by FreeIPA CA:
```
hostname in subject of request 'vault1' does not match name or aliases of principal 'vault/vault1.lab.local@LAB.LOCAL'
```

Status: `CA_REJECTED`, stuck: yes

---

## 3. Analysis (Phase 3)

**Check 1: Certmonger request status**
```bash
getcert list -f /opt/vault/tls/tls.crt
```
Finding: Status shows CA_REJECTED with stuck=yes.

**Check 2: CSR subject inspection**
```
CSR Subject: CN=vault1 (short hostname)
Service Principal: vault/vault1.lab.local@LAB.LOCAL (FQDN)
```
Finding: Subject mismatch - certmonger used `ansible_hostname` (short) instead of FQDN.

**Check 3: FreeIPA principal requirement**
```
FreeIPA validates: CSR subject CN must match service principal hostname
vault1 ≠ vault1.lab.local
```
Finding: FreeIPA requires exact FQDN match with registered service principal.

---

## 4. Root Cause (Phase 3)
> Certmonger generated CSR with subject `CN=vault1` (short hostname from `ansible_hostname`) but service principal was registered as `vault/vault1.lab.local`. FreeIPA requires subject to match the full principal FQDN.

---

## 5. Solution (Phase 3)

**Step 1: Stop stuck tracking request**
```bash
getcert stop-tracking -f /opt/vault/tls/tls.crt
```

**Step 2: Delete existing cert files**
```bash
rm -f /opt/vault/tls/tls.crt /opt/vault/tls/tls.key
```

**Step 3: Update Ansible task with explicit FQDN**
```yaml
- name: Request certificate from FreeIPA
  command: >
    ipa-getcert request
    -K vault/{{ inventory_hostname }}@{{ ipa_realm }}
    -N CN={{ inventory_hostname }}
    -D {{ inventory_hostname }}
    -f /opt/vault/tls/tls.crt
    -k /opt/vault/tls/tls.key
```

**Key flags:**
- `-N CN={{ inventory_hostname }}` - Set subject to FQDN
- `-D {{ inventory_hostname }}` - Set DNS SAN to FQDN

**Lesson:** With `ipa-getcert` and a service principal, always explicitly set `-N` (subject) and `-D` (DNS SAN) to the FQDN.

---
---

# PHASE 4: Ansible Cert Check Failing Hard on Missing File | 2026-03-17

## Symptoms (Phase 4)
Play aborted at "Check current cert issuer" task when `/opt/vault/tls/tls.crt` did not exist.

---

## 3. Analysis (Phase 4)

**Check 1: Task definition**
```yaml
- name: Check current cert issuer
  command: openssl x509 -in /opt/vault/tls/tls.crt -noout -issuer
  register: cert_issuer
```
Finding: No `failed_when` directive - Ansible treats non-zero rc as failure.

**Check 2: OpenSSL behavior on missing file**
```bash
openssl x509 -in /nonexistent/file.crt -noout -issuer
# Error: unable to load certificate
# Exit code: 1
```
Finding: `openssl x509` returns rc=1 when file doesn't exist.

---

## 4. Root Cause (Phase 4)
> `openssl x509` returns `rc=1` when file is missing. Task did not have `failed_when: false` so Ansible treated it as fatal error and aborted the play.

---

## 5. Solution (Phase 4)

**Add `failed_when: false` to treat non-zero rc as handleable condition:**
```yaml
- name: Check current cert issuer
  command: openssl x509 -in /opt/vault/tls/tls.crt -noout -issuer
  register: cert_issuer
  failed_when: false
  changed_when: false

- name: Request certificate if wrong issuer or missing
  command: ipa-getcert request ...
  when: "'ExpectedIssuer' not in cert_issuer.stdout or cert_issuer.rc != 0"
```

**Lesson:** Use `failed_when: false` on probe/check tasks where a non-zero return code is an expected handleable condition.

---
---

# PHASE 5: Ownership Task Failing — Cert Not Written Yet | 2026-03-17

## Symptoms (Phase 5)
"Set correct ownership on TLS files" failed on vault2/vault3:
```
file is absent, cannot continue
```

---

## 3. Analysis (Phase 5)

**Check 1: File existence on failed nodes**
```bash
ls -la /opt/vault/tls/
```
Finding: tls.crt and tls.key files do not exist on vault2/vault3.

**Check 2: Ansible task condition review**
```yaml
# Original condition
when: "'HashiCorp' in cert_issuer.stdout"
```
Finding: Condition only handles existing cert with wrong issuer, not missing files.

**Check 3: cert_issuer registration task**
```bash
openssl x509 -in /opt/vault/tls/tls.crt -issuer -noout
# Returns rc != 0 when file doesn't exist
```
Finding: When file is absent, `cert_issuer.rc != 0` but condition didn't check this.

---

## 4. Root Cause (Phase 5)
> The `when` condition was only checking `'HashiCorp' in cert_issuer.stdout` without handling the case where cert file doesn't exist (`cert_issuer.rc != 0`). This caused the certificate request task to be skipped on vault2/vault3 where files were absent.

---

## 5. Solution (Phase 5)

**Update `when` condition to handle both cases:**
```yaml
when: "'HashiCorp' in cert_issuer.stdout or cert_issuer.rc != 0"
```

**Also recommended:** Use `-w` flag with `ipa-getcert` to wait for cert issuance:
```yaml
- name: Request certificate
  command: >
    ipa-getcert request -w
    ...
```

**Lesson:** Ansible `when` conditions must handle ALL expected states including missing files, not just the happy path.

---
---

# PHASE 6: Shell Expansion on Wrong Node | 2026-03-17

## Symptoms (Phase 6)
All vault nodes tried to connect to `ansible.lab.local:8200` instead of their own hostname.

---

## 3. Analysis (Phase 6)

**Check 1: Command being executed**
```yaml
# Original task
- name: Check Vault status
  command: vault status -address="https://$(hostname -f):8200"
```
Finding: `$(hostname -f)` was expanding to control node hostname on ALL targets.

**Check 2: Shell expansion behavior**
```
Double quotes: "https://$(hostname -f):8200"
- Ansible control node shell processes first
- $(hostname -f) expands to ansible.lab.local
- Command sent to remote: vault status -address="https://ansible.lab.local:8200"
```
Finding: Double quotes cause local shell expansion before remote execution.

---

## 4. Root Cause (Phase 6)
> Double quotes allowed the Ansible control node shell to expand `$(hostname -f)` before the command was sent to remote hosts. All nodes received the same expanded value (control node's hostname).

---

## 5. Solution (Phase 6)

**Escape with backslash to force expansion on the remote node:**
```yaml
command: vault status -address="https://\$(hostname -f):8200"
```

**Better alternative - use Ansible variables:**
```yaml
command: vault status -address="https://{{ inventory_hostname }}:8200"
```

**Lesson:** Use `\$` to escape variables/commands that should expand on the remote node. Prefer Ansible variables when possible.

---
---

# PHASE 7: Vault TLS IP SAN Error | 2026-03-17

## Symptoms (Phase 7)
`vault status` command fails with TLS error:
```
tls: failed to verify certificate for 127.0.0.1 because it doesn't contain any IP SANs
```

---

## 3. Analysis (Phase 7)

**Check 1: VAULT_ADDR environment variable**
```bash
echo $VAULT_ADDR
# (empty)
```
Finding: VAULT_ADDR not set, CLI defaults to `https://127.0.0.1:8200`.

**Check 2: Certificate SAN inspection**
```bash
openssl x509 -in /opt/vault/tls/tls.crt -noout -text | grep -A1 "Subject Alternative Name"
# DNS:vault1.lab.local
```
Finding: Certificate issued for FQDN only, no IP SANs (by design).

---

## 4. Root Cause (Phase 7)
> Vault CLI defaults to `https://127.0.0.1:8200` when `VAULT_ADDR` is not set. Certificate was issued for `vault1.lab.local` without IP SANs. TLS verification fails because 127.0.0.1 is not in the certificate.

---

## 5. Solution (Phase 7)

**Deploy environment file to set VAULT_ADDR:**

**File: `/etc/profile.d/vault.sh`**
```bash
export VAULT_ADDR=https://{{ inventory_hostname }}:8200
export VAULT_CACERT=/etc/ipa/ca.crt
```

**Ansible task:**
```yaml
- name: Deploy Vault environment file
  template:
    src: vault.sh.j2
    dest: /etc/profile.d/vault.sh
    mode: '0644'
```

**Lesson:** Always set `VAULT_ADDR` explicitly. Use `VAULT_CACERT` pointing to the signing CA rather than `VAULT_SKIP_VERIFY=1`.

---
---

# PHASE 8: RPM Post-Install Task Ordering | 2026-03-17

## Symptoms (Phase 8)
Vault RPM post-install script created `/opt/vault/tls`, `/opt/vault/data`, vault user, and self-signed TLS certs before Ansible directory and user tasks ran.

---

## 3. Analysis (Phase 8)

**Check 1: File ownership after install**
```bash
ls -la /opt/vault/
```
Finding: Directories and files created by RPM with different ownership/permissions than expected.

**Check 2: RPM scriptlets**
```bash
rpm -q --scripts vault
```
Finding: Post-install script creates directories, user, and self-signed certs synchronously.

**Check 3: Playbook task order**
```yaml
# Original order
- name: Install Vault
  dnf: name=vault

- name: Create vault user  # <-- TOO LATE
  user: name=vault

- name: Create directories  # <-- TOO LATE
  file: path=/opt/vault/tls
```
Finding: Directory and user tasks placed AFTER install task.

---

## 4. Root Cause (Phase 8)
> Directory and user creation tasks were placed after `dnf install vault` in the playbook. RPM post-install script runs synchronously as part of install — before Ansible continues to the next task.

---

## 5. Solution (Phase 8)

**Reorder tasks: create user/dirs BEFORE install task:**
```yaml
- name: Create vault group
  group:
    name: vault
    system: yes

- name: Create vault user
  user:
    name: vault
    group: vault
    system: yes
    shell: /bin/false

- name: Create directories
  file:
    path: "{{ item }}"
    state: directory
    owner: vault
    group: vault
    mode: '0750'
  loop:
    - /opt/vault
    - /opt/vault/tls
    - /opt/vault/data

- name: Install Vault  # <-- NOW runs AFTER setup
  dnf:
    name: vault
    state: present
```

**Note:** Tasks kept for explicit state enforcement and idempotency even though RPM creates them.

**Lesson:** RPM post-install scripts run synchronously during `dnf install`. Any Ansible tasks that should own resource creation must come BEFORE the install task.

---
---

## 6. Solution Risk
- Risk level: LOW
- Potential impact: None - standard installation and configuration fixes

## 7. Impact After Fix
- Observed: Vault cluster successfully deployed with FreeIPA-signed certificates
- All 3 nodes (vault1, vault2, vault3) running with proper TLS configuration
- No new issues caused by fixes

## 8. Notes

**Summary of Issues Encountered:**

| Phase | Issue | Root Cause |
|-------|-------|------------|
| 1 | GPG validation failed | yum_repository doesn't import GPG key |
| 2 | --force flag unrecognized | Flag doesn't exist in certmonger 0.79 |
| 3 | CSR hostname mismatch | Short hostname vs FQDN in service principal |
| 4 | Cert check fatal on missing file | No failed_when: false on probe task |
| 5 | Ownership task file absent | when condition didn't handle missing files |
| 6 | Shell expansion wrong node | $(hostname) expanded on control node |
| 7 | TLS IP SAN error | VAULT_ADDR not set, defaulted to 127.0.0.1 |
| 8 | RPM post-install ordering | Install task ran before directory setup |

**Key Ansible Patterns Learned:**

```yaml
# Pattern 1: Probe task with handleable failures
- name: Check state
  command: some-check
  register: result
  failed_when: false
  changed_when: false

# Pattern 2: Condition handling all states
when: "result.rc != 0 or 'expected' not in result.stdout"

# Pattern 3: Escape shell expansion for remote
command: some-cmd --value="\$(hostname -f)"

# Pattern 4: Prefer Ansible variables
command: some-cmd --value="{{ inventory_hostname }}"
```

**Verification Commands:**
```bash
# Check vault status across all nodes
ansible vault_cluster -m command \
    -a "bash -c 'source /etc/profile.d/vault.sh && vault status'" \
    -i inventory/inventory.ini

# Check certificate issuer
openssl x509 -in /opt/vault/tls/tls.crt -noout -issuer

# Check certificate SANs
openssl x509 -in /opt/vault/tls/tls.crt -noout -text | grep -A2 "Subject Alternative"

# Check certmonger status
getcert list
```

## 9. Workaround (if any)
> N/A - all issues required proper fixes for production deployment.

