# Git: Remove Sensitive Files from Repository While Keeping Locally

**Case ID**: PLATFORM-017
**Date**: 2026-01-09
**Severity**: High (Security)
**Status**: Resolved
**Category**: Platform / Version Control / Git Security

---

## Problem Summary

Accidentally committed and pushed sensitive files (SSH public keys, certificates, credentials) to a GitHub repository. Need to remove them from the remote repository while preserving local copies needed for infrastructure operations.

**Impact**: Security exposure - sensitive infrastructure files (vault-ca.pub) visible in public/private repository history.

---

## Environment

**Component**: Git Version Control
**Repository**: GitHub (remote)
**Affected Files**:
- `vault-ca.pub` (Vault SSH Certificate Authority public key)
- Potentially: Other `.pub` files, private keys, credentials

**Git Configuration**:
- Remote: GitHub (HTTPS)
- Branch: main
- Working Directory: /opt/workspace/DC-K8s

---

## Symptom

### Initial State

```bash
# File exists in repository
git log --oneline --all -- "03-AUTOMATION/ansible-playbooks/cicd/vault-ca.pub"
# Output: 1b40649 ok (file committed and pushed)

# File visible on GitHub
# URL: https://github.com/USER/REPO/blob/main/03-AUTOMATION/ansible-playbooks/cicd/vault-ca.pub
```

### User Concern

"I accidentally pushed `vault-ca.pub` to GitHub. I need it locally for Ansible playbooks, but don't want it in version control. How do I remove it from GitHub without deleting my local copy?"

---

## Root Cause

### Why This Happened

1. **No .gitignore Protection**: `.pub` files were not excluded in `.gitignore`
2. **Bulk Add Command**: Used `git add .` without reviewing staged files
3. **Missing Pre-commit Validation**: No hooks to prevent sensitive file commits
4. **Lack of Awareness**: Didn't realize public keys should be excluded from version control

### Security Implications

**Why Public Keys Should Not Be in Version Control:**
- Part of security infrastructure (even if "public")
- Reveals certificate authority architecture
- Enables reconnaissance of SSH trust relationships
- Best practice: Infrastructure secrets stay in secure vaults, not git repos

---

## Technical Analysis

### Git's Three Storage Areas

```
┌─────────────────────────────────────────────────────────┐
│                    Git Architecture                      │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  1. Working Directory (Physical Files)                  │
│     - Files on your hard drive                          │
│     - vault-ca.pub exists here                          │
│                                                          │
│  2. Staging Area / Index (Git Cache)                    │
│     - Files prepared for commit (git add)               │
│     - Temporary holding area                            │
│                                                          │
│  3. Repository (Git History)                            │
│     - Committed files in .git folder                    │
│     - Permanent history (requires special tools)        │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### The `--cached` Flag Explained

```bash
# Two ways to remove a file from git:

git rm FILE           # Deletes from disk AND git (DANGEROUS)
git rm --cached FILE  # Removes from git ONLY, keeps on disk (SAFE)
```

**Why `--cached` is Critical:**
- Removes file from git's index (staging area)
- Removes file from git's tracking list
- **Preserves file on your hard drive**
- Next commit will "delete" the file from repository

---

## Solution: Step-by-Step Resolution

### Step 1: Remove from Git Tracking (Keep Local Copy)

```bash
cd /opt/workspace/DC-K8s

# Remove from git tracking but keep on disk
git rm --cached 03-AUTOMATION/ansible-playbooks/cicd/vault-ca.pub

# Output: rm '03-AUTOMATION/ansible-playbooks/cicd/vault-ca.pub'
```

**Verification:**
```bash
# File still exists locally
ls -la 03-AUTOMATION/ansible-playbooks/cicd/vault-ca.pub
# Output: -rw-r--r-- ... vault-ca.pub ✓

# Git shows file as deleted (from tracking)
git status
# Output: deleted: vault-ca.pub (staged for commit)
```

### Step 2: Update .gitignore to Prevent Future Commits

**Before:**
```bash
# SSH keys
*.pem
*.ppk
id_rsa
id_ed25519
*.key
```

**After:**
```bash
# SSH keys and public keys
*.pem
*.ppk
*.pub              # <-- NEW: Block all .pub files
id_rsa
id_rsa.pub         # <-- Explicit (for documentation)
id_ed25519
id_ed25519.pub     # <-- Explicit (for documentation)
*.key
```

**Apply Changes:**
```bash
# Edit .gitignore
vim .gitignore

# Stage the updated .gitignore
git add .gitignore
```

### Step 3: Commit the Changes

```bash
git commit -m "$(cat <<'EOF'
Security: Remove vault-ca.pub from repository and update .gitignore

- Remove vault-ca.pub from git tracking (kept locally)
- Add *.pub to .gitignore to prevent public keys from being committed
- Add comprehensive Jenkins CI/CD setup guide
- Add troubleshooting case: Jenkins Docker nft_compat warnings

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"

# Output: [main 7c28e0d] Security: Remove vault-ca.pub...
```

### Step 4: Push to GitHub

```bash
git push origin main
```

**Result:**
- `vault-ca.pub` removed from GitHub repository
- Local file still exists at `03-AUTOMATION/ansible-playbooks/cicd/vault-ca.pub`
- `.gitignore` now prevents future `.pub` file commits

---

## Verification

### Confirm Local File Preserved

```bash
ls -la 03-AUTOMATION/ansible-playbooks/cicd/vault-ca.pub
# Expected: -rw-r--r-- 1 user user 725 Jan  7 16:31 vault-ca.pub ✓
```

### Confirm Git No Longer Tracks File

```bash
git status
# Expected: Clean working tree (vault-ca.pub not shown)

git ls-files | grep vault-ca.pub
# Expected: No output (file not tracked)
```

### Confirm .gitignore Works

```bash
cd 03-AUTOMATION/ansible-playbooks/cicd/
touch test.pub

git status
# Expected: test.pub does NOT appear in "Untracked files" ✓

rm test.pub  # Clean up test
```

### Confirm GitHub Updated

```bash
# Check remote repository
git ls-tree -r main --name-only | grep vault-ca.pub
# Expected: No output (file removed from remote)
```

**On GitHub Web UI:**
- Navigate to `03-AUTOMATION/ansible-playbooks/cicd/`
- `vault-ca.pub` should not be visible ✓

---

## Advanced: Complete History Removal (Optional)

### Warning

The basic solution (above) removes the file from the **latest version** of the repository. However, the file still exists in **git history** (old commits). For most cases, this is acceptable.

### When Complete History Removal is Needed

- File contains passwords/credentials (not just public keys)
- Compliance requirements mandate complete erasure
- Repository is public and file is highly sensitive

### Commands to Completely Erase File from History

```bash
# WARNING: This rewrites git history - DANGEROUS!
# Only use if absolutely necessary

# Backup your repository first
git clone /opt/workspace/DC-K8s /tmp/DC-K8s-backup

# Remove file from all commits
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch 03-AUTOMATION/ansible-playbooks/cicd/vault-ca.pub" \
  --prune-empty --tag-name-filter cat -- --all

# Verify file removed from history
git log --all --full-history -- "**/vault-ca.pub"
# Expected: No output

# Force push to remote (WARNING: breaks others' clones)
git push origin --force --all
git push origin --force --tags
```

### Risks of History Rewriting

❌ **Breaks collaborator repositories** - Everyone must re-clone
❌ **Destroys forks** - Forks will have old history
❌ **Breaks pull requests** - Open PRs may conflict
❌ **Cannot be undone** - Original history lost forever

**Recommendation**: Only use for critical secrets, not for public keys.

---

## Prevention Measures

### 1. Pre-Commit .gitignore Template

**Add to `.gitignore` at project start:**

```bash
# Sensitive Files - Security
*.pem
*.ppk
*.pub
*.key
*.crt
*.csr
*.p12
*.pfx

# Credentials
credentials.json
secrets.yml
.env
*.env

# SSH Keys
id_rsa
id_rsa.pub
id_ed25519
id_ed25519.pub

# Vault Files
**/vault/keys
**/vault/**/*key*.txt
**/vault/**/*token*
**/vault/**/*root*token*
**/vault/**/*unseal*key*
```

### 2. Git Pre-Commit Hook (Automated Check)

**Create `.git/hooks/pre-commit`:**

```bash
#!/bin/bash
# Pre-commit hook to prevent sensitive files

SENSITIVE_PATTERNS=(
    "\.pub$"
    "\.pem$"
    "\.key$"
    "password"
    "secret"
    "credential"
    "id_rsa"
)

echo "🔍 Checking for sensitive files..."

for pattern in "${SENSITIVE_PATTERNS[@]}"; do
    files=$(git diff --cached --name-only --diff-filter=ACM | grep -E "$pattern" || true)
    if [ ! -z "$files" ]; then
        echo "❌ ERROR: Attempting to commit sensitive files:"
        echo "$files"
        echo ""
        echo "Add these files to .gitignore if they should not be tracked."
        exit 1
    fi
done

echo "✅ No sensitive files detected"
exit 0
```

**Make executable:**
```bash
chmod +x .git/hooks/pre-commit
```

### 3. Always Review Before Committing

```bash
# BAD: Blindly add everything
git add .
git commit -m "updates"

# GOOD: Review what you're adding
git status
git diff --cached
git add -p  # Interactive staging
git commit -m "Security: Add vault integration"
```

### 4. Use Git Aliases for Safety

```bash
# Add to ~/.gitconfig
[alias]
    safe-add = "!git status && read -p 'Review files above. Continue? (y/n) ' -n 1 -r && echo && [[ $REPLY =~ ^[Yy]$ ]] && git add"
    check-sensitive = "!git diff --cached --name-only | grep -E '\\.(pub|pem|key|crt|env)$' && echo 'WARNING: Sensitive files detected!' || echo 'No sensitive files detected.'"
```

**Usage:**
```bash
git safe-add .
git check-sensitive
```

---

## Related Security Best Practices

### Files That Should NEVER Be in Git

**Absolute Never:**
- Private keys (`.pem`, `.key`, `id_rsa`)
- Passwords/credentials (`credentials.json`, `.env`)
- Database dumps with real data
- API tokens/secrets

**Generally Avoid:**
- Public keys (`.pub` files)
- Certificates (`.crt`, `.p12`)
- Configuration with hardcoded IPs/hostnames
- Keytabs (Kerberos authentication)

**Store Instead In:**
- HashiCorp Vault (secrets management)
- Ansible Vault (encrypted variables)
- Cloud provider secret managers (AWS Secrets Manager, etc.)
- Secure environment variables (encrypted CI/CD secrets)

---

## Lessons Learned

### What Went Wrong

1. **Insufficient .gitignore Coverage**
   - `.pub` files were not excluded
   - Template did not cover all sensitive file types

2. **Lack of Pre-Commit Validation**
   - No automated checks before commit
   - Relied on manual review (easy to miss)

3. **Bulk Add Without Review**
   - Used `git add .` without checking staged files
   - Faster but more error-prone

### What Went Right

1. **Quick Detection**
   - Noticed immediately after push
   - Took action before file was widely distributed

2. **Proper Remediation**
   - Used `git rm --cached` to preserve local copy
   - Updated `.gitignore` to prevent recurrence
   - Documented process for team knowledge

3. **Security-First Approach**
   - Treated public keys as sensitive (defense in depth)
   - Prioritized removal over convenience

### Key Takeaways

✅ **Always use .gitignore proactively** - Add patterns before committing sensitive files
✅ **Review staged files before commit** - Use `git status` and `git diff --cached`
✅ **Understand `--cached` flag** - Critical for removing tracked files without deleting locally
✅ **Public keys ≠ Public repository** - Infrastructure files belong in vaults, not git
✅ **Automation prevents mistakes** - Pre-commit hooks catch errors humans miss

---

## Command Reference

### Complete Resolution Commands

```bash
# Step 1: Remove from git tracking (keep locally)
git rm --cached 03-AUTOMATION/ansible-playbooks/cicd/vault-ca.pub

# Step 2: Update .gitignore
echo "*.pub" >> .gitignore

# Step 3: Stage changes
git add .gitignore

# Step 4: Commit
git commit -m "Security: Remove vault-ca.pub and block .pub files"

# Step 5: Push to remote
git push origin main

# Verification
ls -la 03-AUTOMATION/ansible-playbooks/cicd/vault-ca.pub  # File exists ✓
git status                                                  # Clean tree ✓
git ls-files | grep vault-ca.pub                           # No output ✓
```

### Useful Git Commands

```bash
# Check if file is tracked by git
git ls-files | grep FILENAME

# See file in git history
git log --all --full-history -- "**/FILENAME"

# See when file was added/modified
git log --oneline --all -- "path/to/file"

# List all tracked files
git ls-tree -r main --name-only

# Check what .gitignore matches
git check-ignore -v FILENAME
```

---

## Related Cases

- **PLATFORM-016**: ESXi Master AutoProtect Snapshot Performance Degradation (infrastructure management)
- **APPLICATION-002**: Jenkins Docker nft_compat Warnings (infrastructure security)

---

## References

### Documentation

- [Git Removing Files Documentation](https://git-scm.com/docs/git-rm)
- [.gitignore Patterns](https://git-scm.com/docs/gitignore)
- [Git Filter-Branch (History Rewriting)](https://git-scm.com/docs/git-filter-branch)
- [GitHub Security Best Practices](https://docs.github.com/en/code-security/getting-started/best-practices-for-preventing-data-leaks-in-your-organization)

### Security Resources

- [OWASP Top 10: Security Misconfiguration](https://owasp.org/www-project-top-ten/)
- [GitHub Secret Scanning](https://docs.github.com/en/code-security/secret-scanning)
- [GitGuardian (Secret Detection Tool)](https://www.gitguardian.com/)

### Tools

- **git-secrets**: Prevents committing secrets (AWS Labs)
- **pre-commit**: Framework for managing git hooks
- **GitGuardian**: Automated secret scanning
- **truffleHog**: Searches git history for secrets

---

## Appendix: .gitignore Template for Infrastructure Projects

```bash
# Sensitive Files - Passwords, Credentials, Keys
# Note: IP addresses are intentionally kept in documentation for learning purposes

# SSH keys and public keys
*.pem
*.ppk
*.pub
id_rsa
id_rsa.pub
id_ed25519
id_ed25519.pub
*.key

# HashiCorp Vault sensitive files
**/vault/keys
**/vault/**/keys
**/vault/**/*key*.txt
**/vault/**/*token*
**/vault/**/*root*token*
**/vault/**/*unseal*key*
**/vault/**/recovery-keys*

# Credentials and secrets
credentials.json
secrets.yml
.env
*.env

# Certificates (if containing private keys)
*.crt
*.csr
*.p12
*.pfx

# Kubernetes secrets (unencrypted)
**/k8s/secrets/*-local.yaml
**/k8s/secrets/*-unencrypted.yaml
**/k8s/secrets/*-plain.yaml

# Terraform state files
**/*.tfstate
**/*.tfstate.backup
**/.terraform/
**/terraform.tfvars

# Ansible vault files
**/*vault*.yml
**/*secret*.yml
**/*password*.yml

# License keys
licenses/
*.lic

# Backup files
*.bak
*.backup
*.old

# Personal notes
NOTES_PRIVATE.md
TODO_PRIVATE.md
```

---

**Document Version**: 1.0
**Last Updated**: 2026-01-09
**Next Review**: After any security incident or policy update
**Document Owner**: Infrastructure & Security Team
