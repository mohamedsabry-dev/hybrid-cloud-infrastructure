# TS-VLT-001 | 2026-03-17 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Vault / Infrastructure
Sub-techs: HashiCorp Vault, FreeIPA CA, Certmonger, Ansible, DNF/RPM, TLS certificates,
           systemd, Rocky Linux 10, ipa-getcert
Environment: DEV lab.local | 3-node Vault cluster on Rocky Linux 10 LXC containers
             (vault1, vault2, vault3)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Multiple failures encountered during initial Vault cluster deployment on the same day.
This ticket covers the full installation journey across 8 phases — all encountered
and resolved on 2026-03-17.

Issues covered:
  Phase 1 — GPG signature validation failure during DNF install
  Phase 2 — certmonger --force flag not recognized
  Phase 3 — FreeIPA CA rejected CSR due to hostname mismatch
  Phase 4 — Ansible cert check task failing hard on missing file
  Phase 5 — Ownership task failing because cert not written yet
  Phase 6 — Shell expansion running on wrong node
  Phase 7 — Vault TLS IP SAN error
  Phase 8 — RPM post-install task ordering conflict

_____________________________________________________________________

[Analysis]

# Initial Check Notes:

_____________________________________________________________________
PHASE 1 | GPG Signature Validation Failure
_____________________________________________________________________

DNF failed during Vault package installation:
  Failed to validate GPG signature for vault-1.21.4-1.x86_64: Public key not installed
  Additional error on vault3: FileNotFoundError on cached RPM.

Check 1 — RPM GPG keystore:
  Command:
    rpm -q gpg-pubkey --qf '%{NAME}-%{VERSION}-%{RELEASE}\t%{SUMMARY}\n'
  Output:
    HashiCorp GPG key not present in RPM keystore.

Check 2 — Ansible playbook review:
  Current implementation:
    - name: Add HashiCorp repo
      yum_repository:
        name: hashicorp
        baseurl: https://rpm.releases.hashicorp.com/RHEL/$releasever/$basearch/stable
        gpgkey: https://rpm.releases.hashicorp.com/gpg

  Finding: yum_repository adds the GPG key URL to the repo file but does NOT
  import it into the RPM keystore. DNF requires the key physically imported
  via rpm --import before it can verify signed packages.

Root cause: yum_repository and rpm_key are two separate steps on RHEL-family systems.

Fix — clean corrupted cache and add rpm_key task:
  ansible vault_cluster -m command -a "dnf clean all" --become

  Updated playbook:
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

Lesson: yum_repository sets the URL reference. rpm_key does the actual import.
Both are required.


_____________________________________________________________________
PHASE 2 | Certmonger --force Flag Not Recognized
_____________________________________________________________________

ipa-getcert request failed on all 3 nodes:
  unrecognized option --force

Check 1 — Certmonger version:
  Command: rpm -q certmonger
  Output:  certmonger-0.79.20-3.el10

Check 2 — ipa-getcert help:
  Command: ipa-getcert request --help
  Output:  --force flag does not exist in this version.

Root cause: --force flag does not exist in certmonger 0.79.20-3.el10 on Rocky Linux 10.
Flag was incorrectly assumed valid from other documentation or older versions.

Fix — remove --force flag and add separate cleanup task:
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

Lesson: always verify CLI flags against the actual installed version on the target OS.


_____________________________________________________________________
PHASE 3 | FreeIPA CA Rejected CSR — Hostname Mismatch
_____________________________________________________________________

Certificate request rejected by FreeIPA CA:
  hostname in subject of request 'vault1' does not match name or aliases of
  principal 'vault/vault1.lab.local@LAB.LOCAL'
  Status: CA_REJECTED, stuck: yes

Check 1 — Certmonger request status:
  Command: getcert list -f /opt/vault/tls/tls.crt
  Output:  CA_REJECTED, stuck=yes

Check 2 — CSR subject vs service principal:
  CSR Subject:       CN=vault1              (short hostname from ansible_hostname)
  Service Principal: vault/vault1.lab.local  (FQDN)

  FreeIPA validates that CSR subject CN must exactly match service principal hostname.
  vault1 ≠ vault1.lab.local → rejected.

Root cause: certmonger used ansible_hostname (short) in the CSR subject but the
service principal was registered with the FQDN. FreeIPA requires exact FQDN match.

Fix — stop tracking, clean up, re-request with explicit FQDN:
  Step 1: getcert stop-tracking -f /opt/vault/tls/tls.crt
  Step 2: rm -f /opt/vault/tls/tls.crt /opt/vault/tls/tls.key
  Step 3: Updated Ansible task:

    - name: Request certificate from FreeIPA
      command: >
        ipa-getcert request
        -K vault/{{ inventory_hostname }}@{{ ipa_realm }}
        -N CN={{ inventory_hostname }}
        -D {{ inventory_hostname }}
        -f /opt/vault/tls/tls.crt
        -k /opt/vault/tls/tls.key

  Key flags:
    -N CN={{ inventory_hostname }}  sets subject to FQDN
    -D {{ inventory_hostname }}     sets DNS SAN to FQDN

Lesson: with ipa-getcert and a service principal, always explicitly set -N (subject)
and -D (DNS SAN) to the FQDN. Never rely on defaults.


_____________________________________________________________________
PHASE 4 | Ansible Cert Check Failing Hard on Missing File
_____________________________________________________________________

Play aborted at "Check current cert issuer" task when /opt/vault/tls/tls.crt
did not exist on some nodes.

Check 1 — Task definition:
  - name: Check current cert issuer
    command: openssl x509 -in /opt/vault/tls/tls.crt -noout -issuer
    register: cert_issuer
  Finding: no failed_when directive — Ansible treats non-zero rc as fatal failure.

Check 2 — OpenSSL behaviour on missing file:
  openssl x509 -in /nonexistent/file.crt -noout -issuer
  Output:  Error: unable to load certificate
  Exit code: 1 → Ansible treats as fatal, aborts play.

Root cause: openssl x509 returns rc=1 on missing file. No failed_when: false means
Ansible treats it as fatal and aborts. Probe task was not designed to handle
the "file doesn't exist yet" state.

Fix — add failed_when: false and update downstream condition:
  - name: Check current cert issuer
    command: openssl x509 -in /opt/vault/tls/tls.crt -noout -issuer
    register: cert_issuer
    failed_when: false
    changed_when: false

  - name: Request certificate if wrong issuer or missing
    command: ipa-getcert request ...
    when: "'ExpectedIssuer' not in cert_issuer.stdout or cert_issuer.rc != 0"

Lesson: use failed_when: false on probe/check tasks where non-zero rc is an
expected handleable condition, not an error.


_____________________________________________________________________
PHASE 5 | Ownership Task Failing — Cert Not Written Yet
_____________________________________________________________________

"Set correct ownership on TLS files" failed on vault2/vault3:
  file is absent, cannot continue

Check 1 — File existence on failed nodes:
  Command: ls -la /opt/vault/tls/
  Output:  tls.crt and tls.key do not exist on vault2/vault3.

Check 2 — Original task condition:
  when: "'HashiCorp' in cert_issuer.stdout"
  Finding: condition only handles existing cert with wrong issuer.
  Does not handle missing files (cert_issuer.rc != 0).

Check 3 — cert_issuer behaviour:
  When file is absent: cert_issuer.rc != 0 but stdout is empty.
  Condition "'HashiCorp' in cert_issuer.stdout" evaluates to False.
  Certificate request task skipped on vault2/vault3 → files never created.
  Ownership task then tries to act on absent files → fails.

Root cause: when condition was checking stdout only, not handling the rc != 0
(file absent) case. Certificate request skipped, ownership task ran anyway.

Fix — update when condition to handle both states:
  when: "'HashiCorp' in cert_issuer.stdout or cert_issuer.rc != 0"

  Also recommended: use -w flag with ipa-getcert to wait for cert issuance:
    command: >
      ipa-getcert request -w
      ...

Lesson: Ansible when conditions must handle ALL expected states including
missing files — not just the happy path.


_____________________________________________________________________
PHASE 6 | Shell Expansion on Wrong Node
_____________________________________________________________________

All vault nodes tried to connect to ansible.lab.local:8200 instead of
their own hostname.

Check 1 — Original task:
  - name: Check Vault status
    command: vault status -address="https://$(hostname -f):8200"

Check 2 — Shell expansion behaviour with double quotes:
  Double quotes do NOT prevent shell expansion on Ansible control node.
  $(hostname -f) expanded to ansible.lab.local on the control node first.
  Command sent to all remotes: vault status -address="https://ansible.lab.local:8200"
  All nodes queried the control node's hostname instead of their own.

Root cause: double quotes allow Ansible control node shell to expand $(hostname -f)
before the command reaches the remote hosts.

Fix — escape or use Ansible variable:
  Option 1: escape with backslash (force remote expansion)
    command: vault status -address="https://\$(hostname -f):8200"

  Option 2: use Ansible variable (preferred)
    command: vault status -address="https://{{ inventory_hostname }}:8200"

Lesson: use \$ to escape commands/variables that should expand on the remote node.
Prefer Ansible variables ({{ inventory_hostname }}) over shell expansion when possible.


_____________________________________________________________________
PHASE 7 | Vault TLS IP SAN Error
_____________________________________________________________________

vault status command fails with TLS error:
  tls: failed to verify certificate for 127.0.0.1 because it doesn't contain any IP SANs

Check 1 — VAULT_ADDR environment variable:
  Command: echo $VAULT_ADDR
  Output:  (empty)
  Finding: VAULT_ADDR not set — Vault CLI defaults to https://127.0.0.1:8200.

Check 2 — Certificate SAN inspection:
  Command: openssl x509 -in /opt/vault/tls/tls.crt -noout -text | grep -A1 "Subject Alternative Name"
  Output:  DNS:vault1.lab.local
  Finding: cert issued for FQDN only — no IP SANs by design.

Root cause: Vault CLI defaulted to https://127.0.0.1:8200. Certificate was issued
for vault1.lab.local with no IP SANs. TLS verification fails because 127.0.0.1
is not in the certificate.

Fix — deploy environment file to set VAULT_ADDR:
  File: /etc/profile.d/vault.sh
    export VAULT_ADDR=https://{{ inventory_hostname }}:8200
    export VAULT_CACERT=/etc/ipa/ca.crt

  Ansible task:
    - name: Deploy Vault environment file
      template:
        src: vault.sh.j2
        dest: /etc/profile.d/vault.sh
        mode: '0644'

Lesson: always set VAULT_ADDR explicitly. Use VAULT_CACERT pointing to the signing CA
rather than VAULT_SKIP_VERIFY=1.


_____________________________________________________________________
PHASE 8 | RPM Post-Install Task Ordering
_____________________________________________________________________

Vault RPM post-install script created /opt/vault/tls, /opt/vault/data, vault user,
and self-signed TLS certs before Ansible directory and user tasks ran.
Ownership and permissions were set differently than expected.

Check 1 — File ownership after install:
  Command: ls -la /opt/vault/
  Output:  directories and files created by RPM with unexpected ownership/permissions.

Check 2 — RPM scriptlets:
  Command: rpm -q --scripts vault
  Output:  post-install script creates directories, user, and self-signed certs
           synchronously during install.

Check 3 — Original playbook task order:
  - name: Install Vault              ← runs first
    dnf: name=vault
  - name: Create vault user          ← TOO LATE, RPM already ran
    user: name=vault
  - name: Create directories         ← TOO LATE, RPM already ran
    file: path=/opt/vault/tls

Root cause: RPM post-install script runs synchronously as part of dnf install —
before Ansible continues to the next task. User and directory tasks placed after
install task never get to own the initial creation.

Fix — reorder tasks: create user and directories BEFORE install:
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

  - name: Install Vault     ← NOW runs after setup is in place
    dnf:
      name: vault
      state: present

  Note: tasks kept for explicit state enforcement and idempotency even though
  RPM would create them anyway. Ansible owns the state.

Lesson: RPM post-install scripts run synchronously during dnf install. Any Ansible
tasks that should own resource creation must come BEFORE the install task.


# Suspected Root Cause
Eight separate issues encountered sequentially during initial Vault cluster
deployment — each was an independent problem surfacing as the deployment
progressed through installation, certificate provisioning, and configuration.

No single root cause — see individual phase summaries above.


# More Checks Notes:
N/A — all issues encountered and resolved sequentially on the same day.


# Suspected Solution
Per-phase fixes applied progressively throughout the deployment session.


# Test
Full deployment completed successfully across all 3 nodes after all fixes applied.

Command:
  ansible vault_cluster -m command \
    -a "bash -c 'source /etc/profile.d/vault.sh && vault status'" \
    -i inventory/inventory.ini

Result: PASS — Vault cluster deployed with FreeIPA-signed certificates on all nodes.

_____________________________________________________________________

[Final Root Cause]
Eight independent issues encountered during initial Vault cluster deployment.
See phase summaries above for individual root causes. All traced to either:
  - Ansible module behaviour assumptions (yum_repository, failed_when, when conditions)
  - Platform version differences (certmonger --force flag)
  - Shell expansion behaviour in Ansible commands
  - RPM lifecycle vs Ansible task ordering
  - Missing environment configuration (VAULT_ADDR)

_____________________________________________________________________

[Final Solution]
All eight phases resolved on 2026-03-17. Final working playbook incorporates:

  1. rpm_key task after yum_repository for GPG import
  2. --force removed from ipa-getcert, replaced with explicit cleanup task
  3. -N and -D flags set to FQDN in ipa-getcert request
  4. failed_when: false on all probe/check tasks
  5. when conditions handle rc != 0 (missing file) as well as stdout checks
  6. {{ inventory_hostname }} used instead of $(hostname -f)
  7. /etc/profile.d/vault.sh deployed with VAULT_ADDR and VAULT_CACERT
  8. vault user, group, and directories created BEFORE dnf install vault

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Standard installation and configuration fixes — no production impact.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Issue summary:
  Phase 1  GPG validation failed         yum_repository does not import GPG key
  Phase 2  --force flag unrecognized     flag does not exist in certmonger 0.79
  Phase 3  CSR hostname mismatch         short hostname vs FQDN in service principal
  Phase 4  Cert check fatal on missing   no failed_when: false on probe task
  Phase 5  Ownership task file absent    when condition did not handle rc != 0
  Phase 6  Shell expansion wrong node    $(hostname) expanded on control node
  Phase 7  TLS IP SAN error             VAULT_ADDR not set, defaulted to 127.0.0.1
  Phase 8  RPM post-install ordering     install ran before directory/user setup

Key Ansible patterns learned:

  Pattern 1: probe task with handleable failures
    - name: Check state
      command: some-check
      register: result
      failed_when: false
      changed_when: false

  Pattern 2: condition handling all states including missing file
    when: "result.rc != 0 or 'expected' not in result.stdout"

  Pattern 3: escape shell expansion for remote execution
    command: some-cmd --value="\$(hostname -f)"

  Pattern 4: prefer Ansible variables over shell expansion
    command: some-cmd --value="{{ inventory_hostname }}"

  Pattern 5: RPM-aware task ordering
    user/group/directory creation → BEFORE dnf install

Verification commands:
  openssl x509 -in /opt/vault/tls/tls.crt -noout -issuer
  openssl x509 -in /opt/vault/tls/tls.crt -noout -text | grep -A2 "Subject Alternative"
  getcert list
  rpm -q gpg-pubkey --qf '%{NAME}-%{VERSION}-%{RELEASE}\t%{SUMMARY}\n'
  rpm -q --scripts vault