# TS-GH-006 | 2026-03-16 | RESOLVED

## 1. Context
- System: Git repository history
- Environment: hybrid-cloud-infrastructure repository
- Related components: Network interface documentation, test output files

## 2. Issue
- Symptom: Hardware MAC addresses from physical network interfaces committed to git history
- Error: N/A (security audit finding)

**Why MAC addresses are sensitive:**
- Can identify and track physical devices
- Reveal network topology and infrastructure details
- Combined with other data, enable targeted attacks

## 3. Analysis

**Check 1: Search current files for MAC addresses**
```bash
grep -rE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' . --include="*" 2>/dev/null | grep -v ".git/"
```
Finding: MAC address in `storage/drafted_test_raw_output.txt`.

**Check 2: Search git history for MAC addresses**
```bash
git log -p --all | grep -iE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -50
```
Finding: Multiple MAC addresses in deleted files still in history.

**Sensitive data found:**

| # | Type | Location | Status |
|---|------|----------|--------|
| 1 | WiFi Adapter MAC | Deleted server config file | In git history |
| 2 | Ethernet Adapter MAC | Deleted server config file | In git history |
| 3 | USB Ethernet MAC | Test output file | Current file + history |

**Safe findings (example MACs):**
- `AA:BB:CC:DD:EE:FF` - placeholder in docs
- `11:22:33:44:55:66` - placeholder in docs

## 4. Root Cause
> Raw command outputs and server config files containing hardware identifiers were committed before `.gitignore` rules were added. Even after file deletion, git history retains the content.

## 5. Solution
> Redact current files and rewrite git history using git-filter-repo.

**Step 1: Redact current files**
```bash
# Replace real MACs with placeholder
# Before: MAC address is: <REAL_MAC>
# After:  MAC address is: XX:XX:XX:XX:XX:XX
```

**Step 2: Create replacement patterns**
```bash
cat > /tmp/mac-replacements.txt << 'EOF'
<WIFI_MAC>==>XX:XX:XX:XX:XX:XX
<ETHERNET_MAC>==>XX:XX:XX:XX:XX:XX
<USB_ETHERNET_MAC>==>XX:XX:XX:XX:XX:XX
EOF
```

**Step 3: Run git-filter-repo**
```bash
git filter-repo --replace-text /tmp/mac-replacements.txt --force
```

**Step 4: Re-add remote and force push**
```bash
git remote add origin git@github.com:<USERNAME>/<REPO>.git
git push origin --force --all
git push origin --force --tags
```

**Step 5: Verify cleanup**
```bash
git log -p --all | grep -iE '<WIFI_MAC>|<ETHERNET_MAC>'
# Result: No matches
```

## 6. Solution Risk
- Risk level: HIGH (history rewrite)
- Potential impact: All collaborators must re-clone

## 7. Impact After Fix
- Observed: All real MACs replaced with `XX:XX:XX:XX:XX:XX`
- Only placeholder MACs remain in history
- Current files use placeholders

## 8. Notes

**Deep inspection checklist performed:**

| Category | Search Pattern | Result |
|----------|----------------|--------|
| MAC Addresses | `([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}` | Found & cleaned |
| Personal Emails | `@gmail\|@yahoo\|@hotmail` | None exposed |
| AWS Access Keys | `AKIA[A-Z0-9]{16}` | None found |
| GitHub Tokens | `ghp_\|gho_\|github_pat_` | None found |
| Private Keys | `BEGIN.*PRIVATE KEY` | None found |
| Hardcoded Passwords | `password.*=.*['\"]` | Only placeholders |

**Prevention - pre-commit hook:**
```bash
#!/bin/bash
# Block commits containing MAC addresses
if git diff --cached | grep -qE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}'; then
  if git diff --cached | grep -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | \
     grep -qvE '(XX:XX|AA:BB|11:22|00:00|FF:FF)'; then
    echo "ERROR: Commit contains MAC address. Please redact."
    exit 1
  fi
fi
```

**Prevention - .gitignore additions:**
```gitignore
**/test_raw_output*.txt
**/network_scan*.txt
**/interface_discovery*.txt
```

**Related security cleanup chain:**
- TS-GH-003 → Delete workflow logs with exposed secrets
- TS-GH-004 → Git history secrets cleanup (AWS IDs, EIPs, passwords)
- TS-GH-006 (this) → MAC address deep inspection cleanup

## 9. Workaround (if any)
> If history rewrite not possible: ensure current files are redacted and add to .gitignore to prevent future commits.
