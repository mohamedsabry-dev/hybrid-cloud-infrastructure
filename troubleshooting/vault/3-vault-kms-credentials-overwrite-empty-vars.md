# TS-VLT-003 | 2026-03-29 | RESOLVED

## 1. Context
- System: HashiCorp Vault / AWS KMS Auto-Unseal / Ansible
- Environment: 3-node Vault cluster (vault1, vault2, vault3)
- Related components: GitHub Actions workflow, AWS Secrets Manager, Ansible templates
- Related tickets: [TS-VLT-002](2-freeipa-vip-certificate-san-managedby.md) - VIP cert issue (triggered this incident)

## 2. Issue
- Symptom: Vault failed to start on all cluster nodes after running playbook manually
- Error:
```bash
[root@vault1 ~]# systemctl status vault
× vault.service - "HashiCorp Vault - A tool for managing secrets"
     Active: failed (Result: exit-code) since Sun 2026-03-29 20:19:25 EET

[root@vault1 ~]# journalctl -u vault -n 50
Mar 29 20:19:19 vault1 vault[47317]: error parsing Seal configuration: error fetching AWS KMS wrapping key information: NoCredentialProviders: no valid providers in chain. Deprecated.
Mar 29 20:19:19 vault1 vault[47317]:         For verbose messaging see aws.Config.CredentialsChainVerboseErrors
```

Manual start also failed:
```bash
[root@vault1 ~]# /usr/bin/vault server -config=/etc/vault.d/vault.hcl
error parsing Seal configuration: error fetching AWS KMS wrapping key information: NoCredentialProviders: no valid providers in chain. Deprecated.
```

## 3. Analysis

**Check 1: Credentials file on affected nodes**
```bash
[root@vault1 ~]# cat /etc/vault.d/vault.env
# ============================================================================
# VAULT.ENV.J2 - AWS Credentials for KMS Auto-Unseal
# ============================================================================
# Deployed to: /etc/vault.d/vault.env (mode 0600, owner vault)
# Referenced by: systemd vault.service EnvironmentFile
#
# CREDENTIAL SOURCES:
# 1. Environment lookup (workflow) - VAULT_UNSEAL_ACCESS_KEY, VAULT_UNSEAL_SECRET_KEY
# 2. Ansible Vault encrypted (manual) - See group_vars/vault_cluster.yml
# ============================================================================
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
```
Finding: **Credentials were EMPTY on all vault nodes!** ✗

---

**Check 2: Ansible template task**
```yaml
- name: Deploy vault credentials file
  ansible.builtin.template:
    src: templates/vault.env.j2
    dest: /etc/vault.d/vault.env
    owner: vault
    group: vault
    mode: "0600"
  no_log: true
```

Template content (`vault.env.j2`):
```jinja2
AWS_ACCESS_KEY_ID={{ vault_aws_access_key_id }}
AWS_SECRET_ACCESS_KEY={{ vault_aws_secret_access_key }}
```
Finding: Template uses variables that were undefined when run manually. ✓

---

**Check 3: How are credentials normally provided?**
```
GitHub Actions Workflow:
1. Workflow fetches secrets from AWS Secrets Manager
2. Injects as environment variables
3. Ansible picks up from environment
4. Templates into vault.env

Manual Run (what happened):
1. No AWS Secrets Manager fetch
2. Variables undefined/empty
3. Template renders empty values
4. Overwrites valid credentials
```
Finding: Manual run bypassed secret injection step. ✓

---

**Check 4: Timeline of events**
```
1. Vault running fine with valid AWS KMS credentials (deployed via GitHub workflow)
2. During FreeIPA VIP certificate troubleshooting (TS-VLT-002), vault_setup.yml re-run locally
3. Template task overwrote /etc/vault.d/vault.env with empty credentials
4. On next Vault restart (triggered by keepalived setup), Vault failed to start
5. All three nodes (vault1, vault2, vault3) affected
```

## 4. Root Cause
> Playbook designed for GitHub Actions workflow (with AWS secret injection) was run manually from Ansible control node. The `vault_aws_access_key_id` and `vault_aws_secret_access_key` variables were undefined, causing the template to render empty values and overwrite valid credentials.

**Three contributing factors:**
1. **Missing safeguard:** No condition to skip credential deployment when variables empty
2. **Execution context:** Playbook run manually instead of via workflow
3. **Silent overwrite:** Template task completed "successfully" despite empty values

## 5. Solution
> Add safeguard to skip credential deployment when variables are missing.

**Immediate Recovery:**
```bash
# Option 1: Trigger workflow that properly injects AWS credentials
gh workflow run vault-setup.yml

# Option 2: Manually restore (if credentials backed up)
ssh vault1 "cat > /etc/vault.d/vault.env << 'EOF'
AWS_ACCESS_KEY_ID=AKIAXXXXXXXXX
AWS_SECRET_ACCESS_KEY=xxxxxxxxxxxxxxxxxxxxxxxx
EOF
chmod 600 /etc/vault.d/vault.env
chown vault:vault /etc/vault.d/vault.env
systemctl start vault"
```

**Permanent Safeguard:**

**File:** `ansible/dev/playbooks/vault/vault_setup.yml`

```yaml
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
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact: If playbook run without credentials, task skips instead of overwriting - existing credentials preserved

## 7. Impact After Fix
- Observed: Vault started successfully after credentials restored
- VIP certificate working
- Safeguard prevents future accidental overwrites

**Verification:**
```bash
[root@vault1 ~]# cat /etc/vault.d/vault.env | grep -v "^#" | grep -v "^$"
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...

[root@vault1 ~]# systemctl status vault
● vault.service - "HashiCorp Vault - A tool for managing secrets"
     Active: active (running)

[root@ansible ~]# curl https://vault.lab.local:8200
<a href="/ui/">Temporary Redirect</a>.
```

## 8. Notes

**Key Lessons:**
1. **Never run credential-deploying playbooks manually** when credentials come from external secret managers
2. **Always add safeguards** to prevent overwriting critical files with empty values
3. **Use `when` conditions** to skip tasks when required variables undefined/empty
4. **Document execution context** - indicate if playbook must run via workflow vs directly

**Prevention Checklist for credential-sensitive playbooks:**
- [ ] Add `when` conditions checking variables defined AND not empty
- [ ] Add comments indicating required execution context
- [ ] Consider using `creates:` parameter to skip if file exists
- [ ] Log warning if credentials task skipped due to missing vars
- [ ] Test playbook behavior with empty variables before production

**Commands Reference:**
```bash
# Check vault service status
systemctl status vault

# Check vault logs for KMS errors
journalctl -u vault -n 50 --no-pager

# Test vault server manually
/usr/bin/vault server -config=/etc/vault.d/vault.hcl

# Check credentials file (careful with sensitive data)
ls -la /etc/vault.d/vault.env
cat /etc/vault.d/vault.env | head -15

# Restart vault after fixing credentials
systemctl restart vault

# Verify vault is responding
curl https://vault.lab.local:8200
vault status
```

## 9. Workaround (if any)
> Restore credentials from backup or re-run via GitHub Actions workflow which properly injects secrets.

