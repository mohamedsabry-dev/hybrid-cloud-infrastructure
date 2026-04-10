# TS-IDN-009 | 2026-03-20 | RESOLVED

## 1. Context
- System: FreeIPA / Kerberos / GitHub Actions
- Environment: DEV (lab.local)
- Related components: GitHub Actions workflows, AWS Secrets Manager, Ansible

## 2. Issue
- Symptom: Ansible playbook fails to connect using Kerberos authentication after password change
- Error:
```bash
fatal: [vault1.lab.local]: UNREACHABLE! => {
  "msg": "Failed to connect to the host via ssh: super_bot@vault1.lab.local:
  Permission denied (publickey,gssapi-keyex,gssapi-with-mic,password,keyboard-interactive)."
}
```

When running `kinit` with keytab:
```bash
kinit super_bot@LAB.LOCAL -k -t /tmp/super_bot.keytab
kinit: Preauthentication failed while getting initial credentials
```

## 3. Analysis

**Check 1: Verify keytab structure**
```bash
klist -kt /tmp/super_bot.keytab
Keytab name: FILE:/tmp/super_bot.keytab
KVNO Timestamp           Principal
---- ------------------- ------------------------------------------------------
   2 03/06/2026 09:18:30 super_bot@LAB.LOCAL
```
Finding: Keytab appears structurally valid.

**Check 2: Test keytab authentication**
```bash
kinit super_bot@LAB.LOCAL -k -t /tmp/super_bot.keytab
kinit: Preauthentication failed while getting initial credentials
```
Finding: "Preauthentication failed" = keys don't match (not "keytab corrupt").

**Check 3: Check KVNO on FreeIPA server**
```bash
# On FreeIPA server
ipa user-show super_bot --all | grep -i kvno
  krbPrincipalKey: ...
  krblastpwdchange: 20260318143022Z
```
Finding: If KVNO on server is higher than keytab, password was changed after keytab was generated.

**Check 4: Understand how keytabs work**
```
Password → Hash Function → Encryption Keys → Stored in Keytab
                                          → Stored in FreeIPA KDC
```
When password changes, FreeIPA generates NEW keys. Old keytab still has OLD keys = mismatch.

## 4. Root Cause
> The `super_bot` user password was changed **after** the keytab was generated. Keytabs contain encryption keys derived from the password. When password changes, the keytab's keys no longer match FreeIPA's stored keys.

**Keytab is a snapshot** - structurally valid but cryptographically invalid after password change.

## 5. Solution
> Regenerate keytab on FreeIPA server and update AWS Secrets Manager.

**Why this works:** New keytab will have encryption keys matching current password.

**Location:** On FreeIPA server (freeipa.lab.local), then update AWS secret

**Step 1: Regenerate keytab on FreeIPA**
```bash
ssh root@freeipa.lab.local

ipa-getkeytab -s freeipa.lab.local -p super_bot -k /tmp/super_bot.keytab
```

**Step 2: Test new keytab**
```bash
kinit super_bot@LAB.LOCAL -k -t /tmp/super_bot.keytab
klist  # Should show valid ticket
```

**Step 3: Encode and update AWS Secret**
```bash
# Base64 encode
base64 -w 0 /tmp/super_bot.keytab > /tmp/super_bot.keytab.b64

# Update AWS (from machine with AWS access)
aws secretsmanager put-secret-value \
  --secret-id dev/super_bot/keytab \
  --secret-string "$(cat /tmp/super_bot.keytab.b64)"
```

**Step 4: Cleanup**
```bash
rm /tmp/super_bot.keytab /tmp/super_bot.keytab.b64
kdestroy
```

**Verification:**
```bash
# Run GitHub Actions workflow - should now authenticate successfully
```

## 6. Solution Risk
- Risk level: MEDIUM
- Potential impact: See **Issue B** below - regenerating keytab may break password auth

## 7. Impact After Fix
- Observed: Ansible playbooks authenticate successfully
- **New issue discovered:** See Issue B below

---

## Issue B: Keytab Generation Breaks Password Auth

### Discovery
After resolving the initial keytab issue, observed that generating a new keytab **breaks password authentication**.

### Error
```bash
# 1. Reset password
ipa user-mod super_bot --password

# 2. Verify password works
kinit super_bot
# Success - enter new password
kdestroy

# 3. Generate keytab (standard method)
ipa-getkeytab -s freeipa.lab.local -p super_bot -k /tmp/super_bot.keytab

# 4. Try password again
kinit super_bot
kinit: Password incorrect while getting initial credentials

# 5. Keytab works
kinit -k -t /tmp/super_bot.keytab super_bot
# Success
```

### Analysis

**Check 1: FreeIPA directory server logs**
```bash
# On FreeIPA server
grep "super_bot" /var/log/dirsrv/slapd-LAB-LOCAL/access | tail -20
# Shows MOD operation updating krblastpwdchange

ipa user-show super_bot --all | grep krblastpwdchange
# Timestamp matches keytab generation time, NOT password change time
```

Finding: `ipa-getkeytab` modified the user's Kerberos keys.

### Root Cause
> `ipa-getkeytab` without `-r` flag **regenerates new random Kerberos keys**, replacing the password-derived keys.

**What happens internally:**
1. `ipa-getkeytab` generates new random encryption keys
2. Updates `krblastpwdchange` timestamp
3. Password-derived keys are replaced with random keys
4. Keytab contains new random keys → works
5. Password no longer derives matching keys → broken

### Solution: Use `-r` Flag with Directory Manager
> The `-r` (retrieve) flag fetches **existing keys** without regenerating.

**Location:** On FreeIPA server (freeipa.lab.local)

**For accounts where BOTH password and keytab must work:**
```bash
# Reset password first
ipa user-mod super_bot --password

# Verify password works
kinit super_bot
kdestroy

# Retrieve keytab WITHOUT regenerating keys (requires Directory Manager)
LDAPTLS_CACERT=/etc/ipa/ca.crt ipa-getkeytab -r \
  -p super_bot \
  -k /tmp/super_bot.keytab \
  -D "cn=Directory Manager" \
  -w '<DM_PASSWORD>' \
  -H ldaps://freeipa.lab.local

# Now BOTH work:
kinit super_bot              # Password - works
kinit -k -t /tmp/super_bot.keytab super_bot  # Keytab - works
```

### Comparison Table

| Command | Password Auth | Keytab Auth | Use Case |
|---------|---------------|-------------|----------|
| `ipa-getkeytab` (no -r) | Broken | Works | Keytab-only service accounts |
| `ipa-getkeytab -r -D "cn=Directory Manager"` | Works | Works | Need both auth methods |

---

## 8. Notes

**Keytab ≠ Password**

A keytab is a snapshot of encryption keys at a point in time. It becomes invalid when:
- User password changes
- Keytab is regenerated on FreeIPA (old copies become invalid)
- Principal is deleted and recreated

**Keytab Generation ≠ Keytab Retrieval**
- `ipa-getkeytab` (default) = Generate NEW random keys → breaks password
- `ipa-getkeytab -r` = Retrieve EXISTING keys → preserves password

**GitHub Actions workflow fetches keytab like this:**
```yaml
- name: Fetch and Deploy FreeIPA Keytab
  run: |
    # Fetch keytab (stored as base64 SecretString)
    aws secretsmanager get-secret-value \
      --secret-id dev/super_bot/keytab \
      --query SecretString --output text | base64 -d > /tmp/super_bot.keytab

    # Copy to Ansible host
    scp -o StrictHostKeyChecking=no /tmp/super_bot.keytab \
      ${{ env.ANSIBLE_USER }}@${{ env.ANSIBLE_HOST }}:/tmp/super_bot.keytab
```

**Prevention:**
1. Document password changes - keytab must be regenerated
2. Use service accounts - `super_bot` should rarely need password changes
3. Automate keytab rotation in CI/CD
4. Monitor KVNO - track keytab version numbers

## 9. Workaround (if any)
> For keytab-only service accounts (no password needed), just regenerate with standard `ipa-getkeytab`.

## Related Files
- `ansible/dev/playbooks/freeipa/generate_keytab_guide.txt`
- `ansible/prod/playbooks/freeipa/generate_keytab_guide.txt`
- `.github/workflows/dev-vault-full-setup.yml`
- `.github/workflows/prod-vault-full-setup.yml`
