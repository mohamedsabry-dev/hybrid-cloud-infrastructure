# TS-GH-010 | 2026-04-10 | RESOLVED

## 1. Context
- System: Git / GitHub Pull Requests
- Environment: Multi-branch workflow (dev → dev-security → prod)
- Related components: GitHub PR merge settings, long-lived branches

## 2. Issue
- Symptom: Every second merge from dev to prod/dev-security causes conflicts, even when only dev branch is edited
- Error:
```
CONFLICT (content): Merge conflict in <filename>
Automatic merge failed; fix conflicts and then commit the result.

# GitHub PR shows:
"This branch has conflicts that must be resolved"
```

**Observed behavior:**
- First merge of new file: works fine
- Second merge (edit same file): conflict!
- Conflict highlights the exact edit made, as if Git doesn't know previous merge happened
- Pattern repeats on every subsequent edit
- Issue appeared ~2-3 weeks ago after changing merge settings

## 3. Analysis

**Check 1: Review GitHub merge settings**
```
Repository Settings → Pull Requests:
- Allow merge commits: ❌ OFF
- Allow squash merging: ✅ ON  ← PROBLEM
- Allow rebase merging: ✅ ON
```
Finding: Squash merge was enabled and being used for dev→prod PRs.

**Check 2: Examine prod branch commit history**
```bash
git log --oneline prod -10
```
```
23a0d46 Dev (#128)   ← Squash commit (new hash)
8128654 Dev (#126)   ← Squash commit (new hash)
a79671a Dev (#125)   ← Squash commit (new hash)
```
Finding: All commits named "Dev (#xxx)" - these are squash merge commits with new hashes.

**Check 3: Compare commit hashes between branches**
```bash
# Original commit on dev
git log --oneline dev | grep "Add feature X"
# abc1234 Add feature X

# After squash merge to prod
git log --oneline prod | grep "Add feature X"
# (not found - squash created "Dev (#128)" instead)
```
Finding: Squash merge creates entirely new commits. Git cannot track that the original commits are already merged.

## 4. Root Cause
> **Squash merge breaks Git's merge tracking for long-lived branches.**
>
> When you squash merge:
> 1. Git combines all commits into ONE new commit with a NEW hash
> 2. The original commits remain on the source branch with their original hashes
> 3. Git has no way to know the new squash commit contains the same changes
> 4. Next merge: Git sees "unmerged" commits and tries to apply them again → CONFLICT
>
> ```
> SQUASH MERGE FLOW:
>
> dev:  A ─── B ─── C ─── D (edit file)
>                         │
>                         ▼ squash merge
> prod: ─────────── ABC' ───
>                   ↑
>                   New hash! Git doesn't know ABC' = A+B+C
>
> Next merge attempt:
> - Git sees: dev has A,B,C,D and prod has ABC'
> - Git thinks: A,B,C not merged yet (different hashes!)
> - Result: CONFLICT on files touched by A,B,C
> ```

## 5. Solution
> Disable squash/rebase merge and use regular merge commits for long-lived branches.

**Step 1: Update GitHub repo settings**

Go to: Repository → Settings → Pull Requests

| Setting | Change to |
|---------|-----------|
| Allow merge commits | ✅ ON |
| Allow squash merging | ❌ OFF |
| Allow rebase merging | ❌ OFF |

**Step 2: Use "Create a merge commit" for all PRs**

When merging PRs from dev → prod:
- Click the merge button dropdown
- Select "Create a merge commit" (not squash or rebase)

**Step 3: Handle transition period**

After switching from squash to merge commits, you may get ONE more conflict on previously-squashed files. This is because Git still doesn't know about the old squash commits.

Options:
- Resolve this final conflict manually, then future merges will be clean
- Or reset prod to match dev and reapply prod-specific changes (nuclear option)

## 6. Solution Risk
- Risk level: LOW
- Potential impact: One final conflict resolution may be needed during transition

## 7. Impact After Fix
- Observed: Subsequent merges complete without conflicts
- Git properly tracks merged commits
- PRs show only actual new changes

## 8. Notes

**When to use each merge type:**

| Merge Type | Creates New Hash? | Git Tracks Merge? | Use For |
|------------|-------------------|-------------------|---------|
| Merge commit | No (preserves original) | ✅ Yes | Long-lived branches (dev/prod/main) |
| Squash merge | Yes (new combined hash) | ❌ No | Feature branches deleted after merge |
| Rebase merge | Yes (rewrites all hashes) | ❌ No | Feature branches deleted after merge |

**Why squash seemed like a good idea:**

The original reason for enabling squash was to avoid "polluting" dev with prod's history if backward merges (prod→dev) were needed. However:

1. Backward merges should NEVER happen (see TS-GH-008)
2. If prod has changes dev needs, manually copy or cherry-pick them
3. The "cleaner history" benefit of squash is outweighed by the conflict problems

**Related cases:**
- TS-GH-008: Established one-way merge flow rule (dev→prod only)
- This case (TS-GH-010): Adds requirement for regular merge commits (no squash/rebase)

**Complete branching rules:**
1. ONE-WAY FLOW: dev → prod only, never merge backward
2. MERGE TYPE: Always use "Create a merge commit"
3. NO SQUASH: Squash/rebase breaks merge tracking
4. MANUAL COPY: If prod has something dev needs, manually recreate it

## 9. Workaround (if any)
> If squash merge must be used (not recommended), sync branches after each squash:
> ```bash
> # After squash merging dev → prod
> git checkout dev
> git rebase prod
> git push --force-with-lease
> ```
> This is error-prone and not recommended for team workflows.

## 10. References
- TS-GH-008: Git branch merge conflicts (one-way flow rule)
- https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges
