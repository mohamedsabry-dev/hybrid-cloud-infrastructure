# GitHub Troubleshooting Cases

Documentation of issues encountered with GitHub Actions, self-hosted runners, workflows, and git operations.

---

## Cases

| # | File | Issue | Root Cause |
|---|------|-------|------------|
| 1 | [github-runner-stuck-job](1-github-runner-stuck-job.md) | Runner doesn't start after reboot, jobs stuck | Runner service not installed as persistent LaunchDaemon |
| 2 | [workflow-lock-flag-pattern](2-workflow-lock-flag-pattern.md) | Terraform workflows triggered on push destroy resources | No mechanism to lock workflows after setup |
| 3 | [delete-workflow-logs-secrets](3-delete-workflow-logs-secrets.md) | Old workflow logs may contain unmasked secrets | Masking implemented after initial runs |
| 4 | [git-history-secrets-cleanup](4-git-history-secrets-cleanup.md) | Sensitive values in git commit history | Secrets hardcoded before moving to GitHub Secrets |
| 5 | [runner-clock-skew-auth-failure](5-runner-clock-skew-auth-failure.md) | Runner offline with "registration deleted" error | Clock skew from broken DNS/NTP |
| 6 | [mac-address-deep-inspection-cleanup](6-mac-address-deep-inspection-cleanup.md) | Hardware MAC addresses in git history | Raw command outputs committed before .gitignore |
| 7 | [concurrent-terraform-workflow-lxc-reboot](7-concurrent-terraform-workflow-lxc-reboot.md) | Vault workflow fails with exit code 255 | Concurrent Terraform workflows rebooted LXCs |
| 8 | [git-branch-merge-conflicts-flux-gitops](8-git-branch-merge-conflicts-flux-gitops.md) | Cascading merge conflicts between dev/prod branches | Two-way merging between environment branches |

---

## Quick Reference

### Runner Issues
- **Case 1:** Runner not starting → `./svc.sh start` or install as persistent service
- **Case 5:** "Registration deleted" error → Check clock skew first, fix DNS/NTP

### Workflow Safety
- **Case 2:** Lock workflows after setup → Use repository variables as lock flags
- **Case 7:** Exit code 255 → Check if LXCs were rebooted by concurrent workflows

### Git Branch Strategy
- **Case 8:** Merge conflicts → ONE-WAY FLOW ONLY: dev → prod, never merge back

### Security Cleanup Chain (Cases 3→4→6)
Related cases covering full security audit and cleanup:
1. **Case 3:** Delete workflow logs → `gh run list ... | xargs gh run delete {}`
2. **Case 4:** Clean git history (AWS IDs, EIPs, passwords) → `git filter-repo --replace-text`
3. **Case 6:** MAC address cleanup → Same git-filter-repo approach

---

## Related Cases

| Case | Folder | Topic |
|------|--------|-------|
| TS-TF-002 | terraform/ | AWS secrets deletion incident (led to workflow lock pattern) |

---

## Environment

- **Runner:** Mac Mini (macOS) + LXC containers (Rocky Linux)
- **Workflows:** GitHub Actions with self-hosted runners
- **State:** Terraform with S3 + DynamoDB backend
