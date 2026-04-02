# Case 8: Keytab Preauthentication Failed After Password Change

**Date:** 2026-03-20
**Environment:** DEV (lab.local)
**Affected Systems:** GitHub Actions workflows using Kerberos authentication
**Status:** RESOLVED

---

## Symptom

Ansible playbook fails to connect to hosts using `super_bot` user with Kerberos authentication.

### Observed Behavior

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

---

## Root Cause

**The `super_bot` user password was changed after the keytab was generated.**

Keytabs contain encryption keys derived from the user's password. When the password changes:
- Old keytab encryption keys no longer match FreeIPA's stored keys
- Kerberos pre-authentication fails because the keys don't match
- The keytab is structurally valid but cryptographically invalid

### How Keytabs Work

```
Password → Hash Function → Encryption Keys → Stored in Keytab
                                          → Stored in FreeIPA KDC
```

If password changes, FreeIPA generates new keys. Old keytab has old keys = mismatch.

---

## Diagnosis

### Step 1: Verify Keytab Structure

```bash
# Keytab appears valid
klist -kt /tmp/super_bot.keytab
Keytab name: FILE:/tmp/super_bot.keytab
KVNO Timestamp           Principal
---- ------------------- ------------------------------------------------------
   2 03/06/2026 09:18:30 super_bot@LAB.LOCAL
```

### Step 2: Test Keytab Authentication

```bash
kinit super_bot@LAB.LOCAL -k -t /tmp/super_bot.keytab
kinit: Preauthentication failed while getting initial credentials
# ^ This error = keys don't match (password was changed)
```

### Step 3: Check KVNO Mismatch

```bash
# On FreeIPA server - check current KVNO
ipa user-show super_bot --all | grep -i kvno
# If this shows higher KVNO than keytab, password was changed
```

---

## Resolution

### Step 1: Regenerate Keytab on FreeIPA

```bash
ssh root@freeipa.lab.local

ipa-getkeytab -s freeipa.lab.local -p super_bot -k /tmp/super_bot.keytab
```

### Step 2: Test New Keytab

```bash
kinit super_bot@LAB.LOCAL -k -t /tmp/super_bot.keytab
klist  # Should show valid ticket
```

### Step 3: Encode and Update AWS Secret

```bash
# Base64 encode
base64 -w 0 /tmp/super_bot.keytab > /tmp/super_bot.keytab.b64

# Update AWS (from machine with AWS access)
aws secretsmanager put-secret-value \
  --secret-id dev/super_bot/keytab \
  --secret-string "$(cat /tmp/super_bot.keytab.b64)"
```

### Step 4: Cleanup

```bash
rm /tmp/super_bot.keytab /tmp/super_bot.keytab.b64
kdestroy
```

---

## Workflow Keytab Fetch Method

The GitHub Actions workflow fetches keytab as base64 SecretString:

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

---

## Prevention

1. **Document password changes** - Note that keytab must be regenerated
2. **Use service accounts** - `super_bot` should rarely need password changes
3. **Automate keytab rotation** - Consider automating keytab refresh in CI/CD
4. **Monitor KVNO** - Track keytab version numbers

---

## Related Files

- `ansible/dev/playbooks/freeipa/generate_keytab_guide.txt`
- `ansible/prod/playbooks/freeipa/generate_keytab_guide.txt`
- `.github/workflows/dev-vault-full-setup.yml`
- `.github/workflows/prod-vault-full-setup.yml`

---

## Additional Behavior: Keytab Generation Breaks Password Auth

### Discovery

After resolving the initial keytab issue, observed that generating a new keytab **breaks password authentication**.

### Test Sequence

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
# FAILS: "Password incorrect while getting initial credentials"

# 5. Keytab works
kinit -k -t /tmp/super_bot.keytab super_bot
# Success
```

### Root Cause (Confirmed via FreeIPA Logs)

`ipa-getkeytab` without `-r` flag **regenerates new random Kerberos keys**:

```bash
# Check FreeIPA directory server logs
grep "super_bot" /var/log/dirsrv/slapd-LAB-LOCAL/access | tail -20

# Shows MOD operation updating krblastpwdchange
ipa user-show super_bot --all | grep krblastpwdchange
# Timestamp matches keytab generation time, NOT password change time
```

**What happens internally:**
1. `ipa-getkeytab` generates new random encryption keys
2. Updates `krblastpwdchange` timestamp
3. Password-derived keys are replaced with random keys
4. Keytab contains new random keys → works
5. Password no longer derives matching keys → broken

### Solution: Use `-r` Flag with Directory Manager

The `-r` (retrieve) flag fetches **existing keys** without regenerating:

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

### Comparison

| Command | Password Auth | Keytab Auth | Use Case |
|---------|---------------|-------------|----------|
| `ipa-getkeytab` (no -r) | Broken | Works | Keytab-only service accounts |
| `ipa-getkeytab -r -D "cn=Directory Manager"` | Works | Works | Need both auth methods |

### Updated Keytab Generation Guide

For automation accounts where keytab-only is acceptable:
```bash
ipa-getkeytab -s freeipa.lab.local -p super_bot -k /tmp/super_bot.keytab
```

For accounts where both password and keytab must work:
```bash
LDAPTLS_CACERT=/etc/ipa/ca.crt ipa-getkeytab -r \
  -p super_bot \
  -k /tmp/super_bot.keytab \
  -D "cn=Directory Manager" \
  -w '<DM_PASSWORD>' \
  -H ldaps://freeipa.lab.local
```

---

## Key Lesson

**Keytab ≠ Password**

A keytab is a snapshot of encryption keys at a point in time. It becomes invalid when:
- User password changes
- Keytab is regenerated on FreeIPA (old copies become invalid)
- Principal is deleted and recreated

**Keytab Generation ≠ Keytab Retrieval**

- `ipa-getkeytab` (default) = Generate NEW random keys → breaks password
- `ipa-getkeytab -r` = Retrieve EXISTING keys → preserves password
