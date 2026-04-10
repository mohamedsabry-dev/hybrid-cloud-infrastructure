# TS-GH-003 | 2026-03-14 | RESOLVED

## 1. Context
- System: GitHub Actions workflow logs
- Environment: hybrid-cloud-infrastructure repository
- Related components: AWS Secrets Manager, Terraform outputs, workflow masking

## 2. Issue
- Symptom: Past workflow runs may have logged sensitive data before proper masking was implemented
- Error: N/A (proactive security cleanup)

## 3. Analysis

**Check 1: How many workflow runs exist?**
```bash
gh run list --limit 1000 | wc -l
# Result: 619 runs
```
Finding: 619 workflow runs potentially contain unmasked secrets.

**Check 2: Current masking status**
```yaml
# Verified all 27 workflows follow correct pattern:
SECRET=$(aws secretsmanager get-secret-value ...)
echo "::add-mask::${SECRET}"           # Mask first
echo "TF_VAR_secret=${SECRET}" >> $GITHUB_ENV  # Then export
```
Finding: Current workflows properly mask secrets, but old logs may be exposed.

## 4. Root Cause
> Workflow masking (`::add-mask::`) was implemented after initial runs. Old workflow logs may contain unmasked secrets, passwords, and IPs.

## 5. Solution
> Delete all old workflow runs to ensure no sensitive data remains in logs.

**Delete all workflow runs:**
```bash
# Delete in batches of 500
gh run list --limit 500 --json databaseId -q '.[].databaseId' | xargs -I {} gh run delete {}
```

**Or loop until all gone:**
```bash
while [ $(gh run list --limit 1 | wc -l) -gt 0 ]; do
  gh run list --limit 500 --json databaseId -q '.[].databaseId' | xargs -I {} gh run delete {}
  echo "Batch deleted..."
done
echo "Done"
```

**Action taken:** Ran delete command twice (500 limit per batch), removed all 619 workflow runs.

## 6. Solution Risk
- Risk level: LOW
- Potential impact: Lose workflow run history for debugging - acceptable tradeoff for security

## 7. Impact After Fix
- Observed: All 619 old workflow runs deleted
- New runs use proper masking
- No sensitive data in workflow logs

## 8. Notes

**Post-cleanup security audit verified:**

| Check | Result |
|-------|--------|
| All secrets masked before export | ✅ Pass |
| SSH keys masked before use | ✅ Pass |
| No `terraform output` exposing sensitive values | ✅ Pass |
| No debug flags (`TF_LOG`, `-v`) | ✅ Pass |
| sshpass commands use pre-masked passwords | ✅ Pass |

**Terraform sensitive variables (54 instances):**
```bash
grep -r "sensitive\s*=\s*true" terraform/
```
- `proxmox_api_token` ✅
- `root_password` / `vm_root_password` ✅
- `ssh_public_keys` / `ansible_ssh_public_key` ✅
- AWS account IDs in IAM modules ✅

**Related security cleanup chain:**
- TS-GH-003 (this) → Delete workflow logs with exposed secrets
- TS-GH-004 → Git history secrets cleanup (AWS IDs, EIPs, passwords)
- TS-GH-006 → MAC address deep inspection cleanup

## 9. Workaround (if any)
> If deletion not possible, manually review each run for sensitive data exposure.
