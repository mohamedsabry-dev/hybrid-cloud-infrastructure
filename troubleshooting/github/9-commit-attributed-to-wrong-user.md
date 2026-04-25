# TS-GH-009 | 2026-04-10 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Git / GitHub
Sub-techs: Git config, commit attribution, git filter-branch
Environment: Multi-device development (Mac + Tablet)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Commits in private repo showing a different GitHub user (baluluyakalulu) as author.
23 commits attributed to the wrong account despite being made personally.

  Expected: "mohamedsabry-dev committed 3 days ago"
  Actual:   "baluluyakalulu committed 3 days ago"

Private repo, no collaborators — all commits were made by me.

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Checked commit author info in local git log to find what email was being used.

Command:
  git log --all --format="%H %ae %an | %ce %cn" | head -50

Output:
  Mix of commits — some with mohamedsabry.dev@gmail.com, some with admin@localhost.localdomain

Command:
  git log --all --format="%H %an <%ae>" | grep -i "admin@localhost"

Output:
  23 commits made with: admin <admin@localhost.localdomain>

Checked tablet git config:

Command:
  git config user.email
  git config user.name
  hostname

Output:
  user.email  — empty
  user.name   — empty
  hostname    — localhost.localdomain

Tablet had no git identity configured. Git fell back to system defaults and
used admin@localhost.localdomain as the commit email.

Checked if baluluyakalulu is a real account:

Command:
  gh api users/baluluyakalulu

Output:
  Real GitHub account created in 2018 with admin@localhost.localdomain
  registered as their email address.

GitHub matches commit email to registered account emails. When commits with
admin@localhost.localdomain were pushed, GitHub found that email registered to
baluluyakalulu and attributed the commits to that account.


# Suspected Root Cause
Two factors combined. Tablet had no git user config — git used system default
admin@localhost.localdomain. A random GitHub user (baluluyakalulu) had that exact
common default email registered on their account. GitHub attributed all 23 commits
to them.


# More Checks Notes:
N/A — root cause fully confirmed from git log and GitHub API check.


# Suspected Solution
Set git identity on the tablet. Optionally rewrite history to fix the 23 misattributed commits.


# Test
Configured git identity on tablet, made a new commit, pushed.

Command:
  git config --global user.name "mohamedsabry-dev"
  git config --global user.email "mohamedsabry.dev@gmail.com"
  git config --global --list | grep user

Result: PASS — new commits correctly attributed to mohamedsabry-dev on GitHub.

_____________________________________________________________________

[Final Root Cause]
Tablet had no git user config. Git fell back to system defaults and used
admin@localhost.localdomain as the commit email. That common default email
happened to be registered by a real GitHub account (baluluyakalulu, created 2018).
GitHub attributed all 23 commits from the tablet to that account. Not a security
breach — commits are still mine, attribution was just displayed wrong.

_____________________________________________________________________

[Final Solution]
Set git identity on all development devices:

  git config --global user.name "mohamedsabry-dev"
  git config --global user.email "mohamedsabry.dev@gmail.com"

  Verify: git config --global --list | grep user

Optional — rewrite history to fix the 23 old misattributed commits:

  git filter-branch --env-filter '
  if [ "$GIT_AUTHOR_EMAIL" = "admin@localhost.localdomain" ]; then
      export GIT_AUTHOR_NAME="mohamedsabry-dev"
      export GIT_AUTHOR_EMAIL="mohamedsabry.dev@gmail.com"
  fi
  ' --tag-name-filter cat -- --all

  git push --force --all

Verified: Yes (new commits — old commits left as-is, cosmetic only)

_____________________________________________________________________

[Risk Level] LOW (config fix) / MEDIUM (history rewrite)
Note: History rewrite requires force push. Old misattributed commits are
cosmetic only — no security impact if left as-is.

_____________________________________________________________________

[References]
- https://github.com/orgs/community/discussions/181821
- https://stackoverflow.com/questions/64303220/my-commits-appear-as-another-user-in-github

_____________________________________________________________________

[Draft Notes]

How GitHub email attribution works:
  GitHub matches commit email to registered account emails.
  Common default emails like admin@localhost.localdomain, root@localhost,
  user@localhost may already be registered by random accounts worldwide.
  Whoever registered that email first gets the attribution.

Prevention checklist for new devices:
  # Always run on any new machine before first commit
  git config --global user.name "your-github-username"
  git config --global user.email "your-github-email@example.com"

  # Verify before committing
  git config user.name
  git config user.email