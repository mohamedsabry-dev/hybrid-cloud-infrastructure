# TS-IDN-008 | 2026-03-20 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Identity / FreeIPA
Sub-techs: Kerberos, keytab, KVNO, ipa-getkeytab, AWS Secrets Manager, GitHub Actions, Ansible
Environment: DEV lab.local | FreeIPA server freeipa.lab.local | GitHub Actions workflows
Re-opened: No

_____________________________________________________________________

[Issue Description]
Two related issues discovered in sequence — both about keytab and password key mismatch.

Issue A — Ansible playbook fails to connect via Kerberos after password change:
  fatal: [vault1.lab.local]: UNREACHABLE!
  Permission denied (publickey,gssapi-keyex,gssapi-with-mic,password,keyboard-interactive)

  kinit super_bot@LAB.LOCAL -k -t /tmp/super_bot.keytab
  kinit: Preauthentication failed while getting initial credentials

Issue B — Discovered after fixing Issue A: generating a new keytab breaks password auth:
  kinit super_bot
  kinit: Password incorrect while getting initial credentials
  (while keytab still works fine)

_____________________________________________________________________

[Analysis]

# Initial Check Notes:

--- Issue A: keytab preauthentication failure ---

Checked keytab structure first to rule out corruption.

Command:
  klist -kt /tmp/super_bot.keytab

Output:
  KVNO 2 | 03/06/2026 09:18:30 | super_bot@LAB.LOCAL
  Keytab structurally valid.

Tested keytab authentication:

Command:
  kinit super_bot@LAB.LOCAL -k -t /tmp/super_bot.keytab

Output:
  Preauthentication failed — keys don't match (not corrupt, just stale)

Checked when password was last changed on FreeIPA:

Command:
  ipa user-show super_bot --all | grep krblastpwdchange

Output:
  krblastpwdchange: 20260318143022Z

Password was changed after the keytab was generated. Keytab is a snapshot of
encryption keys derived from the password at generation time. When password changes,
FreeIPA generates new keys — old keytab no longer matches.

  Password → hash → encryption keys → stored in keytab AND in FreeIPA KDC
  Password change → new keys in KDC → old keytab keys no longer match → preauthentication fails


# Suspected Root Cause
super_bot password was changed after the keytab was generated. Keytab is
cryptographically invalid — structurally fine but keys don't match FreeIPA KDC anymore.


# More Checks Notes:

--- Issue B: keytab generation breaks password auth ---

After regenerating keytab to fix Issue A, tested both auth methods:

Command:
  kinit super_bot              # password auth
  kinit -k -t /tmp/super_bot.keytab super_bot  # keytab auth

Output:
  kinit super_bot → Password incorrect
  kinit -k -t    → Success

Checked FreeIPA directory server logs:

Command:
  grep "super_bot" /var/log/dirsrv/slapd-LAB-LOCAL/access | tail -20
  ipa user-show super_bot --all | grep krblastpwdchange

Output:
  MOD operation on super_bot at keytab generation time
  krblastpwdchange timestamp matches keytab generation, not password change

ipa-getkeytab without -r flag generates new random Kerberos keys and replaces
the password-derived keys in FreeIPA. Keytab works because it has the new random
keys. Password no longer works because its derived keys were overwritten.

  ipa-getkeytab (no flag) → generates new random keys → updates KDC → keytab works, password broken
  ipa-getkeytab -r        → retrieves existing keys   → no KDC change → both work


# Suspected Solution
Issue A: Regenerate keytab on FreeIPA and update AWS Secrets Manager.
Issue B: Use ipa-getkeytab -r with Directory Manager credentials to retrieve
existing keys without regenerating — preserves password auth.


# Test
Used ipa-getkeytab -r with Directory Manager, tested both auth methods.

Command:
  kinit super_bot
  kinit -k -t /tmp/super_bot.keytab super_bot

Result: PASS — both password and keytab auth work after using -r flag.

_____________________________________________________________________

[Final Root Cause]
Issue A: super_bot password changed after keytab was generated. Keytab is a
snapshot of encryption keys — when password changes, FreeIPA generates new keys
and the old keytab no longer matches. Preauthentication fails.

Issue B: ipa-getkeytab without -r regenerates new random Kerberos keys and
replaces the password-derived keys in FreeIPA KDC. Keytab works with the new
random keys but password auth breaks because its derived keys were overwritten.

_____________________________________________________________________

[Final Solution]

--- Issue A fix ---
Regenerate keytab on FreeIPA and update AWS Secrets Manager:

  # On FreeIPA server
  ipa-getkeytab -s freeipa.lab.local -p super_bot -k /tmp/super_bot.keytab

  # Test
  kinit super_bot@LAB.LOCAL -k -t /tmp/super_bot.keytab
  klist

  # Encode and push to AWS
  base64 -w 0 /tmp/super_bot.keytab > /tmp/super_bot.keytab.b64
  aws secretsmanager put-secret-value \
    --secret-id dev/super_bot/keytab \
    --secret-string "$(cat /tmp/super_bot.keytab.b64)"

  # Cleanup
  rm /tmp/super_bot.keytab /tmp/super_bot.keytab.b64
  kdestroy

--- Issue B fix ---
When both password and keytab must work, use -r flag with Directory Manager:

  # Reset password first and verify it works
  ipa user-mod super_bot --password
  kinit super_bot
  kdestroy

  # Retrieve keytab WITHOUT regenerating keys
  LDAPTLS_CACERT=/etc/ipa/ca.crt ipa-getkeytab -r \
    -p super_bot \
    -k /tmp/super_bot.keytab \
    -D "cn=Directory Manager" \
    -w '<DM_PASSWORD>' \
    -H ldaps://freeipa.lab.local

  Command comparison:
    ipa-getkeytab (no -r)  → new random keys → keytab works, password broken
    ipa-getkeytab -r       → retrieve existing keys → both work

Verified: Yes

_____________________________________________________________________

[Risk Level] MEDIUM
Note: Regenerating keytab without -r breaks password auth for the user.
Any existing keytab copies also become invalid when a new keytab is generated.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Keytab becomes invalid when:
  - User password changes
  - Keytab is regenerated (old copies all become invalid)
  - Principal is deleted and recreated

GitHub Actions workflow fetches keytab from AWS Secrets Manager:
  aws secretsmanager get-secret-value \
    --secret-id dev/super_bot/keytab \
    --query SecretString --output text | base64 -d > /tmp/super_bot.keytab

  scp /tmp/super_bot.keytab user@ansible_host:/tmp/super_bot.keytab

Related files:
  ansible/dev/playbooks/freeipa/generate_keytab_guide.txt
  ansible/prod/playbooks/freeipa/generate_keytab_guide.txt
  .github/workflows/dev-vault-full-setup.yml
  .github/workflows/prod-vault-full-setup.yml

Prevention:
  - super_bot is a service account — avoid password changes unless necessary
  - When password change is needed, always use -r flag to retrieve keytab after
  - Track KVNO to detect stale keytabs early
  - Consider automating keytab rotation in CI/CD