# TS-GH-004 | 2026-03-14 | RESOLVED

## 1. Context
- System: Git repository history
- Environment: hybrid-cloud-infrastructure repository
- Related components: AWS account IDs, Elastic IPs, passwords, SSH keys

## 2. Issue
- Symptom: Sensitive values exposed in git commit history even though current files are clean
- Error: N/A (security audit finding)

**Data found in history:**
| # | Type | Location Found |
|---|------|----------------|
| 1 | AWS Account ID (DEV) | Workflows, docs, terraform defaults |
| 2 | AWS Account ID (PROD) | Workflows, docs, terraform defaults |
| 3 | AWS Elastic IP (wg-dev) | VPN documentation |
| 4 | AWS Elastic IP (wg-prod) | VPN documentation |
| 5 | Password | Terraform config |
| 6 | SSH RSA Public Key | GitHub known hosts |

## 3. Analysis

**Check 1: Search for AWS credentials in history**
```bash
git log -p --all | grep -iE "(aws_account|account_id|AKIA[A-Z0-9]{16})" | head -50
```
Finding: AWS account IDs found in multiple commits.

**Check 2: Search for public IPs (excluding private ranges)**
```bash
git log -p --all | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | sort -u | grep -v "^10\.\|^192\.168\.\|^172\.1[6-9]\.\|^0\.0\.0\.0\|^127\."
```
Finding: AWS Elastic IPs found in VPN documentation.

**Check 3: Verify current files are clean**
```bash
grep -rE "(PATTERN1|PATTERN2|...)" . --include="*" 2>/dev/null | grep -v ".git/" | wc -l
# Result: 0
```
Finding: Current files clean. Only git history contains sensitive values.

## 4. Root Cause
> Secrets were initially hardcoded, then later moved to GitHub Secrets. Git history retains all committed content even after files are modified.

## 5. Solution
> Use git-filter-repo to rewrite history, replacing sensitive values with REDACTED placeholders.

**Step 1: Create replacement file**
```
# cleanup-secrets.txt
literal:<DEV_ACCOUNT_ID>==>REDACTED_AWS_DEV
literal:<PROD_ACCOUNT_ID>==>REDACTED_AWS_PROD
literal:<DEV_EIP>==>REDACTED_EIP_DEV
literal:<PROD_EIP>==>REDACTED_EIP_PROD
literal:<PASSWORD>==>REDACTED_PASSWORD
literal:<SSH_KEY>==>REDACTED_SSH_KEY
```

**Step 2: Backup and run cleanup**
```bash
# Backup .git directory
cp -r .git .git-backup

# Disable branch protection on GitHub

# Run filter-repo
git filter-repo --replace-text cleanup-secrets.txt --force

# Re-add remote (filter-repo removes it)
git remote add origin git@github.com:USERNAME/REPO.git

# Force push ALL branches and tags
git push origin --force --all
git push origin --force --tags

# Delete cleanup file (contains sensitive patterns)
rm cleanup-secrets.txt

# Re-enable branch protection
```

**Step 3: Verify cleanup**
```bash
git log -p --all | grep -E "<SENSITIVE_VALUE>" | head -5
# Result: empty - secrets removed

git log -p --all | grep -E "REDACTED_AWS_DEV|REDACTED_AWS_PROD" | head -10
# Result: REDACTED placeholders confirmed
```

## 6. Solution Risk
- Risk level: HIGH (history rewrite)
- Potential impact: All collaborators must re-clone. Force push required.

## 7. Impact After Fix
- Observed: Git history cleaned, REDACTED placeholders in place
- All clones invalidated (expected)
- No sensitive data in history

**Configuration changes made:**
| Item | Before | After |
|------|--------|-------|
| AWS_ACCOUNT_ID_DEV | Variable | Secret |
| AWS_ACCOUNT_ID_PROD | Variable | Secret |
| PUBLIC_IP | Variable | Renamed to HOME_PUBLIC_IP (Secret) |
| WG_VPN_EIP_DEV | Not tracked | New Secret |
| WG_VPN_EIP_PROD | Not tracked | New Secret |

## 8. Notes

**Prevention - best practices:**
1. Use GitHub Secrets from day one
2. Review diffs before committing
3. Use `.gitignore` for sensitive files
4. Consider pre-commit hooks (`git-secrets`, `gitleaks`)

**Audit commands for future use:**
```bash
# Check terraform for sensitive marking
grep -rE "variable.*(password|token|key|secret)" terraform/ | \
  xargs -I {} grep -L "sensitive" {}

# Check workflows for masking
grep -rE "echo.*\$\{.*\}.*>>" .github/workflows/ | \
  grep -v "add-mask"

# Quick scan for common patterns
git log -p --all | grep -iE "(password|secret|token|key)" | head -100
```

**Key lesson:** Git remembers everything. Clean files doesn't mean clean repo.

**Related security cleanup chain:**
- TS-GH-003 → Delete workflow logs with exposed secrets
- TS-GH-004 (this) → Git history secrets cleanup (AWS IDs, EIPs, passwords)
- TS-GH-006 → MAC address deep inspection cleanup

## 9. Workaround (if any)
> If history rewrite not possible: rotate all exposed credentials immediately.
