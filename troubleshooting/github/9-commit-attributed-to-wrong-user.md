# TS-GH-009 | 2026-04-10 | RESOLVED

## 1. Context
- System: Git / GitHub
- Environment: Multi-device development (Mac + Tablet)
- Related components: Git config, GitHub commit attribution

## 2. Issue
- Symptom: Commits in private repo showing another GitHub user (baluluyakalulu) as the author
- Error:
```
Commits on GitHub displayed with wrong user avatar and profile link
Example: "baluluyakalulu committed 3 days ago" instead of "mohamedsabry-dev committed"
```

**Observed behavior:**
- 23 commits attributed to `baluluyakalulu` account
- Private repo with no collaborators
- User confirmed they made all commits themselves

## 3. Analysis

**Check 1: Local git log author info**
```bash
git log --all --format="%H %ae %an | %ce %cn" | head -50
```
Finding: All commits used same email (`mohamedsabry.dev@gmail.com`) OR `admin@localhost.localdomain`

**Check 2: Identify commits with strange attribution**
```bash
git log --all --format="%H %an <%ae>" | grep -i "admin@localhost"
```
Finding: 23 commits made with `admin <admin@localhost.localdomain>`

**Check 3: Verify tablet git config**
```bash
git config user.email  # Empty
git config user.name   # Empty
hostname               # localhost.localdomain
```
Finding: Tablet had no git config - git fell back to system defaults

**Check 4: Check if baluluyakalulu is real account**
```bash
gh api users/baluluyakalulu
```
Finding: Real GitHub account (created 2018) with `admin@localhost.localdomain` registered as email

## 4. Root Cause
> Two factors combined:
> 1. Tablet had no git user config, so git used system defaults: `admin@localhost.localdomain`
> 2. A random GitHub user (baluluyakalulu) had registered that common default email to their account
>
> When commits with `admin@localhost.localdomain` are pushed to GitHub, GitHub attributes them to whichever account has that email registered - in this case, baluluyakalulu.

## 5. Solution
> Configure git identity on all development devices.

**Location:** Tablet (or any unconfigured device)

**Step 1: Set git config**
```bash
git config --global user.name "mohamedsabry-dev"
git config --global user.email "mohamedsabry.dev@gmail.com"
```

**Step 2: Verify**
```bash
git config --global --list | grep user
```

**Optional: Rewrite history to fix old commits**
```bash
git filter-branch --env-filter '
if [ "$GIT_AUTHOR_EMAIL" = "admin@localhost.localdomain" ]; then
    export GIT_AUTHOR_NAME="mohamedsabry-dev"
    export GIT_AUTHOR_EMAIL="mohamedsabry.dev@gmail.com"
fi
' --tag-name-filter cat -- --all

# Then force push
git push --force --all
```

## 6. Solution Risk
- Risk level: LOW (for config fix) / MEDIUM (for history rewrite)
- Potential impact: Force push required if rewriting history - coordinate with any collaborators

## 7. Impact After Fix
- Observed: New commits from tablet now correctly attributed to mohamedsabry-dev
- Old commits still show baluluyakalulu (unless history is rewritten)

## 8. Notes

**How GitHub email attribution works:**
- GitHub matches commit email to registered GitHub account emails
- Common default emails like `admin@localhost.localdomain`, `root@localhost`, `user@localhost` may be registered by random accounts
- This is NOT a security breach - commits are still yours, just displayed wrong

**Prevention checklist for new devices:**
```bash
# Always run these on new dev machines
git config --global user.name "your-github-username"
git config --global user.email "your-github-email@example.com"

# Verify
git config --global --list | grep user
```

**Test before committing:**
```bash
# Check what identity will be used
git config user.name
git config user.email
```

## 9. Workaround (if any)
> If history rewrite is not desired, the old commits remain with wrong attribution but this is cosmetic only - no security impact.

## 10. References
- https://github.com/orgs/community/discussions/181821
- https://stackoverflow.com/questions/64303220/my-commits-appear-as-another-user-in-github
