# TS-GH-003 | 2026-03-14 | RESOLVED
_____________________________________________________________________

[Info]
Domain: GitHub Actions
Sub-techs: Workflow log masking, AWS Secrets Manager, GitHub CLI, security cleanup
Environment: hybrid-cloud-infrastructure repository
Re-opened: No

_____________________________________________________________________

[Issue Description]
Proactive security cleanup — not a live failure.
Workflow masking (::add-mask::) was implemented after initial runs. Old workflow
logs may contain unmasked secrets, passwords, and IPs from before masking was added.

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Counted how many workflow runs exist and need to be reviewed.

Command:
  gh run list --limit 1000 | wc -l

Output:
  619 runs potentially containing unmasked secrets.

Verified current workflows all follow correct masking pattern:

  SECRET=$(aws secretsmanager get-secret-value ...)
  echo "::add-mask::${SECRET}"                    # mask first
  echo "TF_VAR_secret=${SECRET}" >> $GITHUB_ENV   # then export

All 27 workflows confirmed following correct pattern for new runs.
Problem is historical logs from before masking was implemented.


# Suspected Root Cause
::add-mask:: was added to workflows after the initial runs were already logged.
619 old runs may have secrets, passwords, and IPs in plain text in their logs.


# More Checks Notes:
Verified Terraform sensitive variable coverage:

Command:
  grep -r "sensitive\s*=\s*true" terraform/

Output:
  proxmox_api_token           marked sensitive
  root_password / vm_root_password  marked sensitive
  ssh_public_keys / ansible_ssh_public_key  marked sensitive
  AWS account IDs in IAM modules  marked sensitive
  54 total instances confirmed

Full security audit on current workflow state:
  All secrets masked before export       PASS
  SSH keys masked before use             PASS
  No terraform output exposing secrets   PASS
  No debug flags (TF_LOG, -v)            PASS
  sshpass uses pre-masked passwords      PASS

Current state is clean. Old logs are the only remaining risk.


# Suspected Solution
Delete all 619 old workflow runs. Historical logs gone, no sensitive data remains.


# Test
Ran batch delete command twice (500 limit per batch).

Command:
  gh run list --limit 500 --json databaseId -q '.[].databaseId' \
    | xargs -I {} gh run delete {}

Result: PASS — all 619 runs deleted, only properly masked runs will exist going forward.

_____________________________________________________________________

[Final Root Cause]
Workflow secret masking was implemented after initial workflow runs were already
logged. 619 historical runs potentially contained unmasked secrets, passwords,
and IPs in plain text logs.

_____________________________________________________________________

[Final Solution]
Deleted all old workflow runs in batches of 500 via GitHub CLI:

  # Single batch
  gh run list --limit 500 --json databaseId -q '.[].databaseId' \
    | xargs -I {} gh run delete {}

  # Loop until all gone
  while [ $(gh run list --limit 1 | wc -l) -gt 0 ]; do
    gh run list --limit 500 --json databaseId -q '.[].databaseId' \
      | xargs -I {} gh run delete {}
    echo "Batch deleted..."
  done

All 619 runs removed. New runs use proper masking.

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Workflow run history lost — acceptable tradeoff for removing potential
secret exposure from logs.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Part of a security cleanup chain:
  TS-GH-003 (this)  → delete workflow logs with exposed secrets
  TS-GH-004         → git history secrets cleanup (AWS IDs, EIPs, passwords)
  TS-GH-006         → MAC address deep inspection cleanup