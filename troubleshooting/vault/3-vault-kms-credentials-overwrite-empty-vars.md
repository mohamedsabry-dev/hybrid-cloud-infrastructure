# TS-VLT-003 | 2026-03-29 | RESOLVED | INCIDENT
_____________________________________________________________________

[Info]
Domain: Vault / AWS
Sub-techs: HashiCorp Vault, AWS KMS auto-unseal, Ansible templates, AWS Secrets Manager,
           GitHub Actions, systemd EnvironmentFile
Environment: DEV lab.local | 3-node Vault cluster (vault1, vault2, vault3)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Vault failed to start on all cluster nodes after playbook was run manually.
AWS KMS credentials were wiped — Vault could not authenticate to KMS for auto-unseal.

  systemctl status vault → failed (Result: exit-code)

  journalctl -u vault:
  error parsing Seal configuration: error fetching AWS KMS wrapping key information:
  NoCredentialProviders: no valid providers in chain.

  Manual start also failed:
  /usr/bin/vault server -config=/etc/vault.d/vault.hcl
  → same NoCredentialProviders error

Related ticket: TS-VLT-002 — VIP cert issue (playbook re-run during that investigation triggered this)

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Checked credentials file on affected nodes first.

Command:
  cat /etc/vault.d/vault.env

Output:
  AWS_ACCESS_KEY_ID=
  AWS_SECRET_ACCESS_KEY=
  (both values empty on all three vault nodes)

Checked Ansible template task and template source:

  Template vault.env.j2:
    AWS_ACCESS_KEY_ID={{ vault_aws_access_key_id }}
    AWS_SECRET_ACCESS_KEY={{ vault_aws_secret_access_key }}

  Task:
    ansible.builtin.template:
      src: templates/vault.env.j2
      dest: /etc/vault.d/vault.env
      mode: "0600"

  Finding: template uses variables that were undefined when run manually.
  Template rendered empty values and overwrote the valid credentials on disk.

Traced how credentials are normally provided:

  Via GitHub Actions workflow (normal path):
    1. Workflow fetches secrets from AWS Secrets Manager
    2. Injects as environment variables into Ansible run
    3. Ansible picks up variables from environment
    4. Template renders with real values → vault.env deployed with valid creds

  Via manual run (what happened):
    1. No AWS Secrets Manager fetch step
    2. Variables undefined
    3. Template renders empty values
    4. Overwrites valid credentials that were already on disk
    5. No error — task completed "successfully"

Timeline of events:
  1. Vault running fine with valid AWS KMS credentials (deployed via GitHub workflow)
  2. During TS-VLT-002 VIP certificate troubleshooting, vault_setup.yml re-run locally
  3. Template task overwrote /etc/vault.d/vault.env with empty credentials
  4. On next Vault restart (triggered by keepalived setup), Vault failed to start
  5. All three nodes affected simultaneously


# Suspected Root Cause
Playbook designed for GitHub Actions (with AWS secret injection) was run manually
from Ansible control node. vault_aws_access_key_id and vault_aws_secret_access_key
were undefined — template rendered empty values and silently overwrote valid
credentials. No safeguard existed to prevent overwriting when variables are empty.

What went wrong:
  1. Missing safeguard — no condition to skip credential deployment when vars empty
  2. Execution context — playbook run manually instead of via workflow
  3. Silent overwrite — template task completed successfully despite empty values


# More Checks Notes:
Confirmed all three nodes were in the same state — all affected simultaneously
because the playbook runs against the vault_cluster group.


# Suspected Solution
Immediate: restore credentials and restart Vault.
Permanent: add when condition to skip template task when variables are undefined
or empty — preserve existing credentials instead of overwriting with empty values.


# Test
Restored credentials via GitHub Actions workflow re-run, restarted Vault.

Command:
  cat /etc/vault.d/vault.env | grep -v "^#" | grep -v "^$"
  systemctl status vault
  curl https://vault.lab.local:8200

Result: PASS — credentials present, Vault active and running, VIP responding.

_____________________________________________________________________

[Final Root Cause]
vault_setup.yml was designed to run via GitHub Actions which injects AWS credentials
from Secrets Manager as environment variables. When run manually, those variables
are undefined. The Ansible template rendered empty values and silently overwrote
the valid credentials already on disk. Vault could no longer authenticate to AWS
KMS for auto-unseal — failed on next restart.

_____________________________________________________________________

[Final Solution]

Immediate recovery (either option):
  Option 1: trigger workflow that properly injects AWS credentials
    gh workflow run vault-setup.yml

  Option 2: manually restore credentials
    cat > /etc/vault.d/vault.env << 'EOF'
    AWS_ACCESS_KEY_ID=AKIAXXXXXXXXX
    AWS_SECRET_ACCESS_KEY=xxxxxxxxxxxxxxxxxxxxxxxx
    EOF
    chmod 600 /etc/vault.d/vault.env
    chown vault:vault /etc/vault.d/vault.env
    systemctl start vault

Permanent safeguard — add when condition to credential template task in
ansible/dev/playbooks/vault/vault_setup.yml:

  - name: Deploy vault credentials file
    ansible.builtin.template:
      src: templates/vault.env.j2
      dest: /etc/vault.d/vault.env
      owner: vault
      group: vault
      mode: "0600"
    when:
      - vault_aws_access_key_id is defined
      - vault_aws_access_key_id | length > 0
      - vault_aws_secret_access_key is defined
      - vault_aws_secret_access_key | length > 0
    no_log: true

  Behaviour after fix:
    Manual run without credentials → task skipped, existing file preserved
    Workflow run with credentials  → task runs, file deployed with real values

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: If playbook run without credentials, task skips instead of overwriting.
Existing credentials are preserved — no accidental wipe.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Notes:
  1. Never run credential-deploying playbooks manually when credentials come
     from external secret managers — execution context changes everything
  2. Always add when conditions to prevent overwriting critical files with empty values
  3. Template task completing successfully does not mean content is correct
  4. Document execution context clearly — indicate if playbook must run via workflow
  5. Test playbook behaviour with empty/undefined variables before production

Prevention checklist for credential-sensitive playbooks:
  [ ] Add when conditions: variable defined AND length > 0
  [ ] Comment in playbook: "must run via GitHub Actions workflow"
  [ ] Consider creates: parameter to skip if file already exists
  [ ] Add debug warning task if credential deployment skipped
  [ ] Test with empty vars in staging before promoting to prod

Commands reference:
  systemctl status vault
  journalctl -u vault -n 50 --no-pager
  /usr/bin/vault server -config=/etc/vault.d/vault.hcl   manual test
  ls -la /etc/vault.d/vault.env
  cat /etc/vault.d/vault.env | head -15
  systemctl restart vault
  curl https://vault.lab.local:8200
  vault status