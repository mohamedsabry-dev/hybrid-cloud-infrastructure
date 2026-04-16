# TS-GH-004 | 2026-03-14 | RESOLVED
_____________________________________________________________________

[Info]
Domain: GitHub Actions / Security
Sub-techs: Git history rewrite, git-filter-repo, secrets management, GitHub Secrets
Environment: hybrid-cloud-infrastructure repository
Re-opened: No

_____________________________________________________________________

[Issue Description]
Security audit finding — not a live failure.
Sensitive values found in git commit history even though current files are clean.
Secrets were initially hardcoded, later moved to GitHub Secrets, but git history
retains all committed content even after files are modified.

Data found in history:
  1. AWS Account ID (DEV)    — workflows, docs, terraform defaults
  2. AWS Account ID (PROD)   — workflows, docs, terraform defaults
  3. AWS Elastic IP (wg-dev) — VPN documentation
  4. AWS Elastic IP (wg-prod)— VPN documentation
  5. Password                — terraform config
  6. SSH RSA Public Key      — GitHub known hosts

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Searched git history for sensitive values across all commits and branches.

Command:
  git log -p --all | grep -iE "(aws_account|account_id|AKIA[A-Z0-9]{16})" | head -50

Output:
  AWS account IDs found in multiple commits across workflows, docs, and terraform.

Command:
  git log -p --all | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | sort -u \
    | grep -v "^10\.\|^192\.168\.\|^172\.1[6-9]\.\|^0\.0\.0\.0\|^127\."

Output:
  AWS Elastic IPs found in VPN documentation commits.

Verified current files are clean:

Command:
  grep -rE "(PATTERN1|PATTERN2|...)" . --include="*" 2>/dev/null \
    | grep -v ".git/" | wc -l

Output:
  0 — current files clean. Exposure is in history only.


# Suspected Root Cause
Secrets were hardcoded in early commits then later moved to GitHub Secrets.
Git retains full history of all committed content — cleaning current files does
not remove values from past commits. History is the exposure surface.


# More Checks Notes:
N/A — scope of exposure confirmed from history search results.


# Suspected Solution
Use git-filter-repo to rewrite history, replacing all sensitive values with
REDACTED placeholders across all commits and branches.


# Test
Ran git-filter-repo with replacement file, force-pushed all branches, verified
history no longer contains sensitive values.

Command:
  git log -p --all | grep -E "<SENSITIVE_VALUE>" | head -5
  git log -p --all | grep -E "REDACTED_AWS_DEV|REDACTED_AWS_PROD" | head -10

Result: PASS — first grep returns empty, REDACTED placeholders confirmed in history.

_____________________________________________________________________

[Final Root Cause]
Secrets were hardcoded in early commits and later moved to GitHub Secrets.
Git history retains all committed content permanently. Cleaning current files
does not remove values from past commits — the full diff history was the exposure.

_____________________________________________________________________

[Final Solution]
Rewrote git history using git-filter-repo to replace all sensitive values
with REDACTED placeholders.

  # 1. Create replacement file (cleanup-secrets.txt)
  literal:<DEV_ACCOUNT_ID>==>REDACTED_AWS_DEV
  literal:<PROD_ACCOUNT_ID>==>REDACTED_AWS_PROD
  literal:<DEV_EIP>==>REDACTED_EIP_DEV
  literal:<PROD_EIP>==>REDACTED_EIP_PROD
  literal:<PASSWORD>==>REDACTED_PASSWORD
  literal:<SSH_KEY>==>REDACTED_SSH_KEY

  # 2. Backup and run
  cp -r .git .git-backup
  # Disable branch protection on GitHub first
  git filter-repo --replace-text cleanup-secrets.txt --force

  # 3. Re-add remote (filter-repo removes it)
  git remote add origin git@github.com:USERNAME/REPO.git

  # 4. Force push all branches and tags
  git push origin --force --all
  git push origin --force --tags

  # 5. Cleanup
  rm cleanup-secrets.txt        # contains sensitive patterns
  # Re-enable branch protection

Configuration changes made after cleanup:
  AWS_ACCOUNT_ID_DEV  → moved from Variable to Secret
  AWS_ACCOUNT_ID_PROD → moved from Variable to Secret
  PUBLIC_IP           → renamed to HOME_PUBLIC_IP, moved to Secret
  WG_VPN_EIP_DEV      → new Secret (was not tracked before)
  WG_VPN_EIP_PROD     → new Secret (was not tracked before)

NOTE: All existing clones are invalidated after force push. Re-clone required.

Verified: Yes

_____________________________________________________________________

[Risk Level] HIGH
Note: History rewrite invalidates all collaborator clones. Force push required.
Disable branch protection before running, re-enable after.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Key lesson: git remembers everything. Clean files does not mean clean repo.
Always assume history is permanent and public from day one.

Prevention going forward:
  - Use GitHub Secrets from day one, never hardcode
  - Review diffs before committing
  - Use .gitignore for sensitive files
  - Consider pre-commit hooks (git-secrets, gitleaks)

Audit commands for future use:
  # Check terraform for missing sensitive marking
  grep -rE "variable.*(password|token|key|secret)" terraform/ | \
    xargs -I {} grep -L "sensitive" {}

  # Check workflows for unmasked exports
  grep -rE "echo.*\$\{.*\}.*>>" .github/workflows/ | grep -v "add-mask"

  # Quick scan for common patterns in history
  git log -p --all | grep -iE "(password|secret|token|key)" | head -100

Part of security cleanup chain:
  TS-GH-003       → delete workflow logs with exposed secrets
  TS-GH-004 (this)→ git history cleanup
  TS-GH-006       → MAC address deep inspection cleanup

Workaround if history rewrite is not possible:
  Rotate all exposed credentials immediately.