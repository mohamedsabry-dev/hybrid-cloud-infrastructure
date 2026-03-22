# TS: Delete GitHub Workflow Logs with Exposed Secrets

## Date
2026-03-14

## Problem
Past workflow runs may have logged sensitive data before proper masking was implemented.

---

## Solution

### Delete All Workflow Runs

```bash
# Check count
gh run list --limit 1000 | wc -l

# Delete all (run multiple times if > 500)
gh run list --limit 500 --json databaseId -q '.[].databaseId' | xargs -I {} gh run delete {}
```

### Or Loop Until All Gone

```bash
while [ $(gh run list --limit 1 | wc -l) -gt 0 ]; do
  gh run list --limit 500 --json databaseId -q '.[].databaseId' | xargs -I {} gh run delete {}
  echo "Batch deleted..."
done
echo "Done"
```

---

## Verify Masking Works (After Fresh Runs)

In new workflow logs, secrets should show as `***` not actual values.

Current protections:
- `::add-mask::` in workflows before exporting secrets
- `sensitive = true` on terraform variables
- `sensitive = true` on terraform outputs (EIPs, passwords)

---

## Action Taken

Chose the clean option - deleted all 619 old workflow runs to ensure no sensitive data remains in logs.

```bash
# Ran twice (500 limit per batch)
gh run list --limit 500 --json databaseId -q '.[].databaseId' | xargs -I {} gh run delete {}
```

---

## Post-Cleanup Security Audit

After deleting workflow logs, performed deep check to ensure future runs won't expose secrets.

### Workflow Masking Check ✅

Verified all 27 workflows follow correct pattern:

```yaml
# CORRECT: Mask BEFORE any use or export
SECRET=$(aws secretsmanager get-secret-value ...)
echo "::add-mask::${SECRET}"           # Mask first
echo "TF_VAR_secret=${SECRET}" >> $GITHUB_ENV  # Then export
```

| Check | Result |
|-------|--------|
| All secrets masked before export | ✅ Pass |
| SSH keys masked before use | ✅ Pass |
| No `terraform output` exposing sensitive values | ✅ Pass |
| No debug flags (`TF_LOG`, `-v`) | ✅ Pass |
| sshpass commands use pre-masked passwords | ✅ Pass |

### Terraform Variables Check ✅

All sensitive variables marked with `sensitive = true`:

```bash
# Found 54 instances across all modules
grep -r "sensitive\s*=\s*true" terraform/
```

| Variable Type | Status |
|---------------|--------|
| `proxmox_api_token` | ✅ sensitive = true |
| `root_password` / `vm_root_password` | ✅ sensitive = true |
| `ssh_public_keys` / `ansible_ssh_public_key` | ✅ sensitive = true |
| AWS account IDs in IAM modules | ✅ sensitive = true |

### Terraform Outputs Check ✅

```hcl
# terraform/dev/aws/compute/outputs.tf
output "wireguard_public_ip" {
  sensitive = true  # ✅ Won't show in logs
}
```

### Shell Scripts Check ✅

Scanned all `.sh` files for exposed secrets:

| Check | Result |
|-------|--------|
| Hardcoded passwords | ✅ None (only placeholder "Change_Me") |
| AWS account IDs | ✅ None |
| Public IPs | ✅ None (all private RFC 1918) |
| API tokens/keys | ✅ None (read interactively or from AWS) |
| SSH private keys | ✅ None |

---

## Status
RESOLVED - All 619 workflow runs deleted

## Related
- `45-git-history-secrets-cleanup.md` - Git history cleanup
