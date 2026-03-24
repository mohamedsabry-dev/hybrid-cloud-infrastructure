# TS: Git History Secrets Cleanup

## Date
2026-03-14

## Summary
Comprehensive review and cleanup of sensitive data accidentally committed to git history, including AWS account IDs, public IPs, passwords, and SSH keys.

---

## Background

During routine security review, we identified that sensitive values were exposed in git commit history even though current files were clean. This occurs when:
- Secrets were initially hardcoded, then later moved to GitHub Secrets
- Values were committed before `.gitignore` rules were added
- Configuration changes left traces in commit diffs

---

## Phase 1: Discovery - Scanning Commit History

### Commands Used to Search

**Search for AWS credentials and secrets:**
```bash
git log -p --all | grep -iE "(aws_account|account_id|AKIA[A-Z0-9]{16}|secret.*=|password.*=|token.*=|private_key|BEGIN.*PRIVATE)" | head -50
```

**Search for 12-digit AWS account IDs:**
```bash
git log -p --all | grep -oE '\b[0-9]{12}\b' | sort -u
```

**Search for public IPs (excluding private ranges):**
```bash
git log -p --all | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | sort -u | grep -v "^10\.\|^192\.168\.\|^172\.1[6-9]\.\|^172\.2[0-9]\.\|^172\.3[0-1]\.\|^0\.0\.0\.0\|^127\."
```

**Search for SSH keys:**
```bash
git log -p --all | grep -oE "ssh-rsa AAAAB3NzaC1[A-Za-z0-9+/=]+" | sort -u
git log -p --all | grep -oE "ssh-ed25519 AAAAC3[A-Za-z0-9+/]+" | sort -u
```

**Search for passwords:**
```bash
git log -p --all | grep -iE "(password.*=.*['\"])" | head -30
```

---

## Phase 2: Findings

### Sensitive Data Found in Git History

| # | Type | Location Found |
|---|------|----------------|
| 1 | AWS Account ID (DEV) | Workflows, docs, terraform defaults |
| 2 | AWS Account ID (PROD) | Workflows, docs, terraform defaults |
| 3 | AWS Account ID (old) | Terraform variable defaults |
| 4 | AWS Elastic IP (wg-dev) | VPN documentation |
| 5 | AWS Elastic IP (wg-prod) | VPN documentation |
| 6 | Password | Terraform config |
| 7 | SSH RSA Public Key | GitHub known hosts |

### Verification - Current Files Were Clean

Before cleanup, we verified current working directory had no sensitive data:

```bash
# Comprehensive check for all identified sensitive values
grep -rE "(PATTERN1|PATTERN2|...)" . --include="*" 2>/dev/null | grep -v ".git/" | wc -l
# Result: 0
```

**Conclusion:** Current files were clean. Only git history contained the sensitive values.

---

## Phase 3: Cleanup - Using git-filter-repo

### Step 1: Create Replacement File

Created `cleanup-secrets.txt` with replacement expressions:

```
# Format: literal:OLD==>NEW

# AWS Account IDs
literal:<DEV_ACCOUNT_ID>==>REDACTED_AWS_DEV
literal:<PROD_ACCOUNT_ID>==>REDACTED_AWS_PROD
literal:<OLD_ACCOUNT_ID>==>REDACTED_AWS_ID

# AWS Elastic IPs
literal:<DEV_EIP>==>REDACTED_EIP_DEV
literal:<PROD_EIP>==>REDACTED_EIP_PROD

# Passwords
literal:<PASSWORD>==>REDACTED_PASSWORD

# SSH Keys
literal:<SSH_KEY>==>REDACTED_SSH_KEY
```

### Step 2: Install git-filter-repo

```bash
brew install git-filter-repo
```

### Step 3: Backup and Run Cleanup

```bash
# Backup .git directory
cp -r .git .git-backup

# Disable branch protection on GitHub (required for force push)

# Run filter-repo (rewrites ALL history)
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

---

## Phase 4: Validation

### Verify Secrets Removed

```bash
# Each command should return empty (no output)
git log -p --all | grep -E "<SENSITIVE_VALUE>" | head -5
```

**Result:** All searches returned empty - secrets successfully removed.

### Verify Replacements Applied

```bash
# Should show REDACTED_* values
git log -p --all | grep -E "REDACTED_AWS_DEV|REDACTED_AWS_PROD" | head -10
git log -p --all | grep -E "REDACTED_EIP_DEV|REDACTED_EIP_PROD" | head -10
```

**Result:** REDACTED placeholders confirmed in history.

---

## Phase 5: Configuration Changes

### Moved from Variables to Secrets

| Item | Before | After | Reason |
|------|--------|-------|--------|
| AWS_ACCOUNT_ID_DEV | Variable | Secret | Account IDs should be hidden |
| AWS_ACCOUNT_ID_PROD | Variable | Secret | Account IDs should be hidden |

### Renamed Secrets

| Old Name | New Name | Reason |
|----------|----------|--------|
| PUBLIC_IP | HOME_PUBLIC_IP | More descriptive |

### New Secrets Added

| Secret Name | Purpose |
|-------------|---------|
| WG_VPN_EIP_DEV | WireGuard VPN Elastic IP (dev) |
| WG_VPN_EIP_PROD | WireGuard VPN Elastic IP (prod) |

### Files Updated

1. **Workflows:**
   - `dev-aws-compute.yml` - Changed `secrets.PUBLIC_IP` → `secrets.HOME_PUBLIC_IP`
   - `prod-aws-compute.yml` - Same change + removed terraform import step

2. **Documentation:**
   - `github/variables-secrets.md` - Updated secrets/variables list
   - `Re-Deployment Guide.txt` - Updated secret names
   - `network/vpn-setup/wireguard-setup.md` - EIPs now show as REDACTED

---

## Current GitHub Configuration

### Repository Secrets

| Secret Name | Purpose |
|-------------|---------|
| AWS_ACCOUNT_ID_DEV | DEV AWS account ID |
| AWS_ACCOUNT_ID_PROD | PROD AWS account ID |
| HOME_PUBLIC_IP | Home public IP for security groups |
| VPN_PUBLIC_KEY_DEV | SSH public key for DEV VPN EC2 |
| VPN_PUBLIC_KEY_PROD | SSH public key for PROD VPN EC2 |
| WG_VPN_EIP_DEV | WireGuard VPN Elastic IP (dev) |
| WG_VPN_EIP_PROD | WireGuard VPN Elastic IP (prod) |
| GH_ADMIN_PAT | GitHub admin PAT for deploy keys |
| DEV_GH_RUNNER_TOKEN | DEV runner registration token |
| PROD_GH_RUNNER_TOKEN | PROD runner registration token |

### Repository Variables

| Variable Name | Value | Purpose |
|---------------|-------|---------|
| AWS_REGION_DEV | us-east-1 | DEV AWS region |
| AWS_REGION_PROD | eu-west-2 | PROD AWS region |
| *_LOCK | true/false | Workflow lock flags |
| *_GH_RUNNER_* | various | Runner configuration |

---

## Prevention - Best Practices

### 1. Never Commit Secrets
- Use GitHub Secrets from day one
- Use environment variables, not hardcoded values
- Review diffs before committing

### 2. Use .gitignore
```gitignore
# Keys and credentials
*.pem
*.key
.env
*.tfvars

# Backup configs with credentials
*.cfg
backup-*.bin
```

### 3. Pre-commit Hooks
Consider using tools like:
- `git-secrets` - Prevents committing secrets
- `trufflehog` - Scans for secrets in history
- `gitleaks` - Detects hardcoded secrets

### 4. Regular Audits
Periodically scan history:
```bash
# Quick scan for common patterns
git log -p --all | grep -iE "(password|secret|token|key)" | head -100
```

---

## Key Lessons

1. **Git remembers everything** - Even if you fix current files, the history retains old values
2. **Validate both current AND history** - Clean files doesn't mean clean repo
3. **Force push required** - History rewrite requires force push to all branches
4. **Collaborators must re-clone** - After history rewrite, all clones are invalid
5. **Move sensitive data to secrets early** - Prevents cleanup complexity later

---

## Phase 6: Post-Cleanup Security Audit

After cleaning git history, performed comprehensive audit to prevent future exposure.

### Terraform Security Check

**Variables (54 instances verified):**
```bash
grep -r "sensitive\s*=\s*true" terraform/
```

| Variable Type | Modules | Status |
|---------------|---------|--------|
| `proxmox_api_token` | All proxmox modules | ✅ sensitive = true |
| `root_password` | LXC, VM modules | ✅ sensitive = true |
| `vm_root_password` | FreeIPA, K8s modules | ✅ sensitive = true |
| `ssh_public_keys` | LXC modules | ✅ sensitive = true |
| `ansible_ssh_public_key` | VM modules | ✅ sensitive = true |
| AWS account IDs | IAM modules | ✅ sensitive = true |

**Outputs:**
```hcl
# terraform/*/aws/compute/outputs.tf
output "wireguard_public_ip" {
  sensitive = true  # ✅ EIP won't show in plan/apply
}
```

### Workflow Security Check

Verified all 27 workflows in `.github/workflows/`:

| Pattern | Status |
|---------|--------|
| `::add-mask::` called before `$GITHUB_ENV` export | ✅ All workflows |
| No `terraform output -raw` with sensitive values | ✅ Only in comments |
| No debug flags (`TF_LOG`, `--debug`) | ✅ None found |
| SSH key injection masked before use | ✅ All workflows |

**Correct masking order verified:**
```yaml
# Step 1: Fetch
SECRET=$(aws secretsmanager get-secret-value ...)

# Step 2: Mask IMMEDIATELY
echo "::add-mask::${SECRET}"

# Step 3: Then export (value now hidden in logs)
echo "TF_VAR_secret=${SECRET}" >> $GITHUB_ENV
```

### Shell Scripts Security Check

Scanned all 12 shell scripts (`**/*.sh`):

| File | Check | Result |
|------|-------|--------|
| `bootstrap-*.sh` | TOKEN_ID is name only, not value | ✅ Safe |
| `network-setup-*.sh` | WiFi password via `read -s` (interactive) | ✅ Safe |
| `mail-config.sh` | Gmail password via `read -sp` (interactive) | ✅ Safe |
| `setup-wireguard.sh` | Keys generated at runtime | ✅ Safe |
| `golden-*.sh` | Password refs in comments only | ✅ Safe |
| `create-emergency-user.sh` | Placeholder "Change_Me" only | ✅ Safe |

**IP addresses found - all private:**
- `10.0.x.x` - Internal VLANs (RFC 1918)
- `172.16.x.x`, `172.17.x.x` - VPN tunnels (RFC 1918)
- `192.168.100.x` - Local network (RFC 1918)
- `8.8.8.8` - Google DNS (public, safe)

### Audit Commands for Future Use

```bash
# Check terraform for sensitive marking
grep -rE "variable.*(password|token|key|secret)" terraform/ | \
  xargs -I {} grep -L "sensitive" {}

# Check workflows for masking
grep -rE "echo.*\$\{.*\}.*>>" .github/workflows/ | \
  grep -v "add-mask"

# Check shell scripts for secrets
grep -rE "(password|token|secret).*=" --include="*.sh" | \
  grep -v "read -s" | grep -v "#"

# Check for public IPs in shell scripts
grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' **/*.sh | \
  grep -v "^10\.\|^192\.168\.\|^172\.1[6-9]\.\|^8\.8\.8\.8"
```

---

## Status
RESOLVED - Git history cleaned, secrets migrated, documentation updated

## Related Files
- `github/variables-secrets.md` - Secrets/variables documentation
- `Re-Deployment Guide.txt` - Deployment reference
- `.gitignore` - Updated ignore patterns
- `44-delete-workflow-logs.md` - Workflow logs cleanup
