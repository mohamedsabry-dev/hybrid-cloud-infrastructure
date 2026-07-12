OIDC Trust Chain — GitHub to AWS to Proxmox (Summary Trace)
=============================================================

pre-trace (one-time setup):
  OIDC provider registered in AWS IAM (trusts GitHub-signed tokens)
    → two IAM roles: TerraformAdmin (bootstrap, env-security branch)
      creates → Infrastructure (day-to-day, env branch)
        both capped by TerraformPermissionsBoundary
    → Proxmox API token (tf_env@pve, API-only) stored in AWS Secrets Manager

developer pushes to env branch
  → GitHub Actions triggers workflow → job starts on self-hosted mac-mini
    → configure-aws-credentials action requests JWT from GitHub OIDC internally
      → JWT signed with claims: repo, branch, actor, audience=sts.amazonaws.com

→ JWT + target role ARN sent to AWS STS (AssumeRoleWithWebIdentity)
  → AWS validates: OIDC provider registered? audience matches? sub claim
    matches repo+branch? signature valid against GitHub public key?
      → all 4 pass → STS returns 3 temporary credentials (1 hour, no renewal):
        AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY + AWS_SESSION_TOKEN
          → injected as masked env vars in runner + written to $GITHUB_ENV on disk

→ aws secretsmanager get-secret-value → fetches Proxmox token JSON blob
  → ::add-mask:: on raw blob immediately
    → JSON parsed → token_id + token_secret extracted
      → 4 mask variations applied (blob, id, secret, combined)
        → written to $GITHUB_ENV as TF_VAR_proxmox_api_token
          → TF_VAR_ prefix = Terraform reads from env automatically

→ terraform init -upgrade → acquires DynamoDB lock on state
  → terraform plan → every AWS API call carries assumed role token
    → IAM evaluates each call independently (authorization is per-request,
      not pre-checked at assume time — fail one call, rest unaffected)
        → plan output saved → 3-minute safety window for human review

→ terraform apply -auto-approve
  → AWS resources: API calls authorized per-request by IAM
    → state written incrementally per-resource (not batched at end)
  → Proxmox resources: API calls use token from Secrets Manager
    → Proxmox checks ACL per-call (same pattern as AWS)
      → DynamoDB lock held for entire apply → apply completes → lock released

→ workflow ends
  → AWS temp creds expire after 1 hour (no renewal, no IP binding)
    → if apply exceeds 1 hour: current call fails, state reflects last write,
      lock stays held → recovery: force-unlock → plan to check drift
  → Proxmox token: permanent, stays in Secrets Manager
  → self-hosted runner: creds exist on disk until cleanup
    → GitHub-hosted runner: VM wiped, creds gone
