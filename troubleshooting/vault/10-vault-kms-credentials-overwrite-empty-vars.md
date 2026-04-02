# Case 10: Vault KMS Auto-Unseal Credentials Overwritten by Empty Ansible Variables

**Component:** HashiCorp Vault | AWS KMS | Ansible | GitHub Actions
**Date:** March 29, 2026

---

## Symptom

After running the Vault setup playbook directly from the Ansible control node (instead of via GitHub Actions workflow), Vault failed to start on all cluster nodes:

```
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

---

## Investigation Flow

### Step 1: Check Credentials File

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

**Finding:** Credentials were EMPTY on all vault nodes.

### Step 2: Identify the Cause

The playbook task that deploys credentials:

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

**Root Cause:** When running the playbook directly from the Ansible control node, the variables `vault_aws_access_key_id` and `vault_aws_secret_access_key` were undefined/empty because:

1. The GitHub Actions workflow normally fetches these secrets from AWS Secrets Manager and injects them as environment variables
2. Running locally bypassed this secret injection step
3. Ansible templated empty values, overwriting the valid credentials that were previously deployed

### Step 3: Timeline of Events

1. Vault was running fine with valid AWS KMS credentials (deployed via GitHub workflow)
2. During FreeIPA VIP certificate troubleshooting, the `vault_setup.yml` playbook was re-run locally
3. The template task overwrote `/etc/vault.d/vault.env` with empty credentials
4. On next Vault restart (triggered by keepalived setup), Vault failed to start due to missing KMS credentials
5. All three nodes (vault1, vault2, vault3) were affected

---

## Root Cause Summary

1. **Missing Safeguard:** No condition to skip credential deployment when variables are empty
2. **Execution Context:** Playbook designed for GitHub Actions workflow (with AWS secret injection) was run manually
3. **Silent Overwrite:** Template task completed "successfully" despite templating empty values

---

## Fix Applied

### Immediate Recovery

Restore credentials via GitHub Actions workflow, which fetches from AWS Secrets Manager:

```bash
# Trigger the workflow that properly injects AWS credentials
gh workflow run vault-setup.yml
```

Or manually restore (if you have the credentials backed up):

```bash
ssh vault1 "cat > /etc/vault.d/vault.env << 'EOF'
AWS_ACCESS_KEY_ID=AKIAXXXXXXXXX
AWS_SECRET_ACCESS_KEY=xxxxxxxxxxxxxxxxxxxxxxxx
EOF
chmod 600 /etc/vault.d/vault.env
chown vault:vault /etc/vault.d/vault.env
systemctl start vault"
```

### Permanent Safeguard

Updated `ansible/dev/playbooks/vault/vault_setup.yml` to skip deployment if credentials are missing:

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

---

## Verification After Fix

### Credentials Restored

```bash
[root@vault1 ~]# cat /etc/vault.d/vault.env | grep -v "^#" | grep -v "^$"
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
```

### Vault Started Successfully

```bash
[root@vault1 ~]# systemctl status vault
● vault.service - "HashiCorp Vault - A tool for managing secrets"
     Active: active (running)
```

### VIP Certificate Working

```bash
[root@ansible ~]# curl https://vault.lab.local:8200
<a href="/ui/">Temporary Redirect</a>.
```

---

## Lesson Learned

1. **Never run credential-deploying playbooks manually** when credentials come from external secret managers (AWS Secrets Manager, HashiCorp Vault, etc.)
2. **Always add safeguards** to prevent overwriting critical files with empty values
3. **Use `when` conditions** to skip tasks when required variables are undefined or empty
4. **Consider making credentials file immutable** after initial deployment (chattr +i) or using a different mechanism
5. **Document the execution context** — clearly indicate if a playbook must be run via workflow vs. directly

---

## Prevention Checklist

For credential-sensitive playbooks:

- [ ] Add `when` conditions to check variables are defined AND not empty
- [ ] Add comments in playbook indicating required execution context
- [ ] Consider using `creates:` parameter to skip if file exists
- [ ] Log a warning if credentials task is skipped due to missing vars
- [ ] Test playbook behavior with empty variables before production use

---

## Commands Reference

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

---

## Related Cases

- Case 63: FreeIPA VIP Certificate SAN — Managedby Permissions (triggered the re-run)
- Case 07: Secrets Deletion Incident (similar category of credential management issues)
