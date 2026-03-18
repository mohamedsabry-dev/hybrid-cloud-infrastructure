# TS: MAC Address & Deep Security Inspection Cleanup

## Date
2026-03-16

## Summary
Comprehensive deep inspection and cleanup of MAC addresses and other sensitive hardware identifiers from git history, following up on previous secrets cleanup.

---

## Background

During a security audit, we identified that hardware MAC addresses from physical network interfaces were committed to git history in documentation and test output files. Even though the files were later deleted or modified, the sensitive data remained in git commit history.

### Why MAC Addresses Are Sensitive
- Can be used to identify and track physical devices
- May reveal network topology and infrastructure details
- Combined with other data, can enable targeted attacks

---

## Phase 1: Discovery - Scanning for MAC Addresses

### Commands Used

**Search current files for MAC addresses:**
```bash
grep -rE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' . --include="*" 2>/dev/null | grep -v ".git/"
```

**Search git history for MAC addresses:**
```bash
git log -p --all | grep -iE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -50
```

**Find specific commits containing MAC addresses:**
```bash
for commit in $(git rev-list --all); do
  git show "$commit" | grep -q 'XX:XX:XX:XX:XX:XX' && echo "$commit"
done
```

---

## Phase 2: Findings

### Sensitive Data Found

| # | Type | Location | Status |
|---|------|----------|--------|
| 1 | WiFi Adapter MAC | Deleted server config file | In git history |
| 2 | Ethernet Adapter MAC | Deleted server config file | In git history |
| 3 | USB Ethernet MAC | Test output file | Current file + history |
| 4 | USB Ethernet MAC | Deleted server config file | In git history |

### Files Affected

| File | Status |
|------|--------|
| `proxmox/08-proxmox-server-config.txt` | Deleted (but in history) |
| `storage/drafted_test_raw_output.txt` | Current file |

### Safe Findings (Example/Placeholder MACs)

| Location | Value | Status |
|----------|-------|--------|
| `poc-v1/infrastructure/network/03-Internal-Network.md` | `AA:BB:CC:DD:EE:FF` | Safe - example |
| `poc-v1/infrastructure/network/03-Internal-Network.md` | `11:22:33:44:55:66` | Safe - example |

---

## Phase 3: Deep Inspection Checklist

### Areas Inspected

| Category | Search Pattern | Result |
|----------|----------------|--------|
| MAC Addresses | `([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}` | Found & cleaned |
| Personal Emails | `@gmail\|@yahoo\|@hotmail` | None exposed |
| AWS Access Keys | `AKIA[A-Z0-9]{16}` | None found |
| GitHub Tokens | `ghp_\|gho_\|github_pat_` | None found |
| Private Keys | `BEGIN.*PRIVATE KEY` | None found |
| Vault Tokens | `hvs\.[A-Za-z0-9]+` | Previously cleaned |
| Vault Unseal Keys | `Unseal Key [0-9]:` | Previously cleaned |
| Hardcoded Passwords | `password.*=.*['\"]` | Only placeholders |
| Public IPs | Non-private IP ranges | Only infrastructure IPs |
| Phone Numbers | `[0-9]{10,}` | None found |
| Financial Data | `credit.*card\|ssn\|bank` | None found |

### Workflow & PR Inspection

| Area | Method | Result |
|------|--------|--------|
| `.github/workflows/` | Direct grep | Clean |
| Git commit history | `git log -p --all` | Cleaned |
| PR merge commits | Commit message review | No sensitive data |
| Deleted files | `git log --diff-filter=D` | Cleaned |

### Current Files Verification

```bash
# Verify no real MACs remain (excluding placeholders)
grep -rE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' . --include="*" 2>/dev/null | \
  grep -v ".git/" | \
  grep -v "XX:XX:XX" | \
  grep -v "AA:BB:CC" | \
  grep -v "11:22:33"
# Result: No matches
```

---

## Phase 4: Cleanup Process

### Step 1: Redact Current Files

```bash
# Edit current files to replace real MACs with placeholder
# storage/drafted_test_raw_output.txt
# Before: MAC address is: <REAL_MAC>
# After:  MAC address is: XX:XX:XX:XX:XX:XX
```

### Step 2: Create Replacement Patterns File

```bash
cat > /tmp/mac-replacements.txt << 'EOF'
<WIFI_MAC>==>XX:XX:XX:XX:XX:XX
<ETHERNET_MAC>==>XX:XX:XX:XX:XX:XX
<USB_ETHERNET_MAC>==>XX:XX:XX:XX:XX:XX
EOF
```

### Step 3: Run git-filter-repo

```bash
git filter-repo --replace-text /tmp/mac-replacements.txt --force
```

### Step 4: Verify Cleanup

```bash
# Confirm no real MACs in history
git log -p --all | grep -iE '<WIFI_MAC>|<ETHERNET_MAC>|<USB_ETHERNET_MAC>'
# Result: No matches
```

### Step 5: Re-add Remote and Force Push

```bash
# git-filter-repo removes remotes, re-add it
git remote add origin git@github.com:<USERNAME>/<REPO>.git

# Force push all branches and tags
git push origin --force --all
git push origin --force --tags
```

---

## Phase 5: Post-Cleanup Verification

### Final Inspection Results

| Check | Command | Result |
|-------|---------|--------|
| MAC in history | `git log -p --all \| grep -E '([0-9a-fA-F]{2}:){5}'` | Only placeholders |
| Vault tokens | `git log -p --all \| grep 'hvs\.'` | Shows `hvs.REDACTED` |
| Unseal keys | `git log -p --all \| grep 'Unseal Key'` | Shows `VAULT_UNSEAL_KEY_REDACTED` |
| Current files | `grep -r 'XX:XX:XX'` | Placeholder only |

---

## Prevention Measures

### 1. Pre-commit Hooks

Add to `.git/hooks/pre-commit`:
```bash
#!/bin/bash
# Block commits containing MAC addresses
if git diff --cached | grep -qE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}'; then
  # Allow known safe patterns
  if git diff --cached | grep -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | \
     grep -qvE '(XX:XX|AA:BB|11:22|00:00|FF:FF)'; then
    echo "ERROR: Commit contains MAC address. Please redact before committing."
    exit 1
  fi
fi
```

### 2. .gitignore Additions

```gitignore
# Test outputs that may contain hardware info
**/test_raw_output*.txt
**/network_scan*.txt
**/interface_discovery*.txt
```

### 3. Documentation Guidelines

- Always use placeholder MACs in documentation: `XX:XX:XX:XX:XX:XX`
- Never commit raw command output containing hardware identifiers
- Review files before committing infrastructure documentation

---

## Related Documents

- [TS: Git History Secrets Cleanup](ts-git-history-secrets-cleanup.md) - Initial secrets cleanup
- [07: Secrets Deletion Incident](../security/07-secrets-deletion-incident.md) - Incident response

---

## Commands Quick Reference

```bash
# Search for MAC addresses in current files
grep -rE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' .

# Search for MAC addresses in git history
git log -p --all | grep -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}'

# Deep inspection - all sensitive patterns
git log -p --all | grep -iE \
  '(([0-9a-fA-F]{2}:){5}|AKIA|ghp_|hvs\.|BEGIN.*PRIVATE|password.*=)'

# Clean with git-filter-repo
git filter-repo --replace-text replacements.txt --force

# Verify cleanup
git log -p --all | grep '<PATTERN>' | wc -l
```

---

## Lessons Learned

1. **Test outputs are risky** - Raw command outputs often contain hardware identifiers
2. **Deleted files persist** - Git history retains all committed content
3. **Regular audits needed** - Schedule periodic security scans of git history
4. **Defense in depth** - Use pre-commit hooks + .gitignore + code review
