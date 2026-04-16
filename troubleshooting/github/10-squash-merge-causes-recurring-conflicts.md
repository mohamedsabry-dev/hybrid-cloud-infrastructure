# TS-GH-010 | 2026-04-10 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Git / GitHub
Sub-techs: Git merge strategy, squash merge, merge commit, branch protection, PR settings
Environment: Multi-branch workflow (dev → dev-security → prod)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Every second merge from dev to prod/dev-security causes conflicts, even when only
dev branch is edited. Pattern started ~2-3 weeks ago after changing merge settings.

  First merge of a new file    → works fine
  Second merge (edit same file)→ CONFLICT

  "This branch has conflicts that must be resolved"
  CONFLICT (content): Merge conflict in <filename>

Conflict highlights the exact edit made — as if Git has no memory of the previous merge.

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Reviewed GitHub merge settings since the pattern started after a settings change.

Repository Settings → Pull Requests:
  Allow merge commits:  OFF
  Allow squash merging: ON   ← in use for dev→prod PRs
  Allow rebase merging: ON

Checked prod branch commit history:

Command:
  git log --oneline prod -10

Output:
  23a0d46 Dev (#128)   ← squash commit, new hash
  8128654 Dev (#126)   ← squash commit, new hash
  a79671a Dev (#125)   ← squash commit, new hash

All merges named "Dev (#xxx)" — squash commits with entirely new hashes.

Compared original commit hashes between dev and prod:

Command:
  git log --oneline dev | grep "Add feature X"
  git log --oneline prod | grep "Add feature X"

Output:
  dev:  abc1234 Add feature X
  prod: (not found — squash created "Dev (#128)" instead)

The original commits exist on dev but are not traceable on prod. Git has no way
to know the squash commit contains those changes.

What squash merge does:
  dev:  A ─── B ─── C ─── D (edit file)
                          │
                          ▼ squash merge
  prod: ─────────── ABC' ───  ← new hash, Git has no record of A, B, C

  Next merge attempt:
  Git sees dev has A, B, C, D and prod has ABC' (unknown to dev)
  Git thinks A, B, C were never merged
  Result: conflict on every file those commits touched


# Suspected Root Cause
Squash merge was being used for dev→prod PRs. Squash creates a new combined commit
with a new hash, discarding the original commit identities. Git cannot track that the
squash commit contains those changes. On the next merge, Git sees the original commits
as unmerged and tries to apply them again — conflict.


# More Checks Notes:
Confirmed the divergence scale — 20+ files in conflict across all branches due to
accumulated squash merges over several weeks. Manual conflict resolution was impractical.


# Suspected Solution
Disable squash/rebase merge in repo settings, use regular merge commits only.
Reset all branches to dev (source of truth) to clear accumulated divergence.


# Test
Reset all branches to dev, made a test edit on dev, merged to prod using merge commit.

Command:
  git rev-list --left-right --count origin/dev...origin/prod

Result: PASS — 0 0, branches identical. Second merge of same file had no conflict.

_____________________________________________________________________

[Final Root Cause]
Squash merge was enabled and used for dev→prod PRs. Squash combines all commits into
one new commit with a new hash — original commit hashes are discarded. Git uses commit
hashes to track what has been merged. On the next merge, Git sees the original commits
on dev, finds no matching hashes on prod, and treats them as unmerged. Conflict on
every file those commits touched. Pattern repeats on every subsequent edit.

_____________________________________________________________________

[Final Solution]
Two parts — fix settings, reset branches.

Part A: GitHub repo settings:
  Allow merge commits:  ON
  Allow squash merging: OFF
  Allow rebase merging: OFF

Part B: Nuclear reset — sync all branches to dev:

  # 1. Create backups
  git checkout prod-security && git branch prod-security-backup-20260410
  git checkout prod          && git branch prod-backup-20260410
  git checkout dev-security  && git branch dev-security-backup-20260410
  git checkout main          && git branch main-backup-20260410

  # 2. Disable branch protection on GitHub temporarily

  # 3. Reset each branch to dev
  git checkout prod && git reset --hard origin/dev && git push origin prod --force
  git checkout prod-security && git reset --hard origin/dev && git push origin prod-security --force
  git checkout dev-security && git reset --hard origin/dev && git push origin dev-security --force
  git checkout main && git reset --hard origin/dev && git push origin main --force

  # 4. Verify
  git rev-list --left-right --count origin/dev...origin/prod          # 0 0
  git rev-list --left-right --count origin/dev...origin/prod-security # 0 0
  git rev-list --left-right --count origin/dev...origin/dev-security  # 0 0
  git rev-list --left-right --count origin/dev...origin/main          # 0 0

  # 5. Re-enable branch protection

Going forward — always select "Create a merge commit" when merging PRs.
Never use squash or rebase for dev→prod or any long-lived branch merges.

Related: TS-GH-008 — established one-way merge flow rule (dev→prod only).
This case adds the merge commit type requirement on top of that.

Complete branching rules:
  1. ONE-WAY FLOW    → dev → prod only, never merge backward
  2. MERGE TYPE      → always use "Create a merge commit"
  3. NO SQUASH       → squash/rebase breaks merge tracking on long-lived branches
  4. MANUAL COPY     → if prod has something dev needs, manually recreate in dev

Verified: Yes

_____________________________________________________________________

[Risk Level] MEDIUM
Note: Force push to multiple branches required. Any unique commits on target
branches are lost — backed up first. Team members need to re-sync local copies
after force push: git fetch && git reset --hard origin/<branch>

_____________________________________________________________________

[References]
- TS-GH-008 — one-way merge flow rule
- https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges

_____________________________________________________________________

[Draft Notes]

Merge type comparison:
  Merge commit  → preserves original hashes, Git tracks merge history  ← use for dev/prod
  Squash merge  → new combined hash, Git loses tracking                ← only for feature branches deleted after merge
  Rebase merge  → rewrites all hashes, same problem as squash          ← only for feature branches deleted after merge

Why squash seemed like a good idea originally:
  Wanted to avoid polluting dev with prod history if backward merges were needed.
  But backward merges should never happen (TS-GH-008), and the "cleaner history"
  benefit of squash is completely outweighed by the recurring conflict problem.

Alternative if nuclear reset is not acceptable:
  Manually resolve all conflicts once — after that painful merge, future merges
  with merge commits will be clean.
  git checkout prod && git merge dev
  # resolve each conflict, keeping correct version
  git add . && git commit && git push