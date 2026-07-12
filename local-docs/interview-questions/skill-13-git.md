Skill 13 — Git (5 questions)
=============================

Format: Standard questions only. Project examples are ammunition.
Your force-push cluster outage (TS-K8S-049), squash-merge tracking
break, one-way copy pattern for dev→prod, no feature branches decision,
filter-repo incident — inject when the bridge is earned.

---

1. What is the difference between merge and rebase — when do you use each?

   Coverage check:
   - merge: creates merge commit, preserves full history
   - rebase: replays commits on top of target, linear history
   - fast-forward merge (when possible, no merge commit)
   - interactive rebase (squash, reorder, edit commits)
   - golden rule: never rebase published/shared branches
   - squash merge — when useful, how it breaks Git's merge tracking
   - fetch vs pull (fetch = download, pull = fetch + merge)

2. How do you resolve a merge conflict?

   Coverage check:
   - why conflicts happen (same lines changed in both branches)
   - conflict markers (<<<<<<<, =======, >>>>>>>)
   - resolution workflow (edit file, stage, commit)
   - tools (vimdiff, VS Code merge editor)
   - rebase conflicts (resolve per-commit, continue)
   - testing after resolution (don't just pick one side blindly)

3. Explain branching strategies — GitFlow, trunk-based, GitHub Flow.

   Coverage check:
   - GitFlow (develop, feature, release, hotfix — heavier)
   - trunk-based (main branch, short-lived branches, CI/CD-friendly)
   - GitHub Flow (main + feature branches, PR-based)
   - which fits which team size and release cadence
   - environment branches (deploy from branch = environment)
   - feature flags as alternative to long-lived branches

4. How do you undo changes in Git?

   Coverage check:
   - git reset --soft (undo commit, keep staged)
   - git reset --mixed (undo commit, unstage, keep files)
   - git reset --hard (undo everything, destructive)
   - git revert (create inverse commit, safe for public history)
   - git stash (shelve work temporarily, pop to restore)
   - git reflog (recovery — find lost commits after reset)
   - git checkout vs git restore vs git switch (modern commands)
   - detached HEAD state and how to recover

5. What is cherry-pick and when would you use it?

   Coverage check:
   - apply a specific commit from one branch to another
   - use case: hotfix on main needs to go to release branch
   - cherry-pick vs merge (single commit vs full branch)
   - conflict handling during cherry-pick
   - risks (duplicate commits, diverging history)
   - git bisect for debugging (binary search through commits)
