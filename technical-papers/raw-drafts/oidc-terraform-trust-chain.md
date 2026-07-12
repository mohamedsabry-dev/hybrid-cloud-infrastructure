OIDC Trust Chain — GitHub to AWS to Proxmox
============================================

Traces how a GitHub Actions workflow authenticates to AWS via OIDC,
fetches the Proxmox API token from Secrets Manager, and runs Terraform
apply against both AWS and Proxmox. Covers the one-time trust setup,
the runtime signal flow, and every known gap.


### The Two IAM Roles

Two separate roles, created at different times, with different privilege:

    TerraformAdmin (bootstrap, CloudFormation)
      |
      +-- created manually, one-time
      +-- branch: env-security (strict PR approvals, no forks, no contributors)
      +-- AdministratorAccess (AWS managed policy)
      +-- ceiling: TerraformPermissionsBoundary
      +-- this role creates the next one
      |
      +-- Infrastructure (created by TerraformAdmin via Terraform)
            +-- branch: env (not security branch)
            +-- PowerUserAccess (full except IAM and Organizations)
            +-- ceiling: TerraformPermissionsBoundary (same as admin)
            +-- additional deny: SecurityBoundary policy
            +-- this role does day-to-day infra work

    bootstrap also creates a GUI admin user (admin_env) with
    AdministratorAccess + Billing for manual console management.


### OIDC Provider — The Trust Foundation

    AWS IAM → Identity Providers → OpenID Connect

    tells AWS to trust GitHub as a signed identity source.
    not scoped to any repo or account yet — general trust with
    GitHub's OIDC service.

    provider URL:   token.actions.githubusercontent.com
    audience:       sts.amazonaws.com
    ThumbprintList: exists in config but ignored since July 2023 —
                    AWS handles CA verification internally now.
                    parameter still required by the CloudFormation schema,
                    so it stays with whatever value.

the OIDC provider is referenced by both IAM roles. it's the gate that
says "yes, I trust tokens signed by GitHub." the scoping to specific
repos and branches happens in the role's condition block, not here.


### Permissions Boundary — Bootstrap Self-Protection

the TerraformPermissionsBoundary is attached to both roles as a ceiling.
it prevents them from touching the bootstrap resources:

    denied:
      - OIDC provider (can't remove the trust foundation)
      - S3 state bucket (can't delete or modify state storage)
      - DynamoDB lock table (can't break the locking mechanism)
      - its own IAM role and boundary policy (can't self-modify)

    everything else: allowed (subject to the role's own policies)

a permissions boundary is a ceiling — it doesn't grant anything,
it limits what can be granted. the role's policy says "you can do X,"
the boundary says "but never Y." both must allow for the action to work.


### The Intentional Privilege Escalation

the boundary does NOT prevent TerraformAdmin from creating new IAM roles
that have no boundary attached. this means a privilege escalation path
exists: the admin role can create a child role with authority over
resources the admin itself is blocked from (OIDC, state bucket, etc).

this is intentional. the admin role is the programmatic root of trust
for the account. restricting it from creating privileged child roles
would break the purpose of having it — bootstrap requirements evolve,
and the admin needs full authority to build the trust hierarchy.

the real security gate is the branch. env-security requires strict PR
approvals, no fork workflow triggers, no contributors. if that branch
is compromised, the whole account is at risk by design.


### The Infrastructure Role — Day-to-Day Operations

created by TerraformAdmin via Terraform. two deny layers on top of
PowerUserAccess:

    1. inherited from bootstrap:
         cannot touch core state/lock/OIDC resources
         (same boundary as admin)

    2. SecurityBoundary policy (deny, not a boundary):
         cannot mutate IAM
         cannot touch CloudTrail
         cannot touch billing
         allows PassRole ONLY to wireguard-ssm-role for EC2

the PassRole exception is scoped to one specific role ARN. it lets
Terraform attach an instance profile to the WireGuard EC2. without it,
EC2 can't assume the SSM role it needs for management.

technically, if someone has write access to the env branch and can
modify Terraform config, they could pass a different role to EC2.
constrained by branch protection and ARN scoping. accepted for now.


### Proxmox API Token — The Other Side

the Proxmox bootstrap creates two users:

    admin_env@pam (PAM realm)
      +-- real Linux OS user on the Proxmox host
      +-- can SSH, use sudo, access shell
      +-- for human admins who need GUI + shell access
      +-- password managed at Linux level (passwd)

    tf_env@pve (PVE realm)
      +-- Proxmox internal database only
      +-- does NOT exist at OS level — no SSH, no shell
      +-- can only interact through Proxmox API or web GUI
      +-- for automation accounts like Terraform
      +-- if the token leaks: attacker can only make API calls,
          cannot pivot to the OS

    PAM = Linux system auth (real user, full access)
    PVE = Proxmox internal DB (API only, no OS existence)

the Terraform token is created with:

    pveum acl modify "/" --users tf_env@pve --roles Administrator
    pveum user token add tf_env@pve tk1 --privsep 0 --expire 0

    --privsep 0: token inherits ALL permissions of parent user.
                 since parent has Administrator on / (root ACL),
                 this token has full admin access to everything.
                 if --privsep 1 (default), the token would need
                 its own separate ACL entries.

    --expire 0:  token never expires.

combined: permanent full-admin key. same design philosophy as the
TerraformAdmin role — broad authority, controlled at the access layer.

important caveat: --privsep 0 gives the token the full permissions
of the parent user, but the bpg/proxmox Terraform PROVIDER doesn't
implement every Proxmox API endpoint. some storage-level and
cluster-level actions fail not because the token lacks privilege,
but because the provider doesn't call the right API path.
API token scope and API provider coverage are two different things.


### Secret Storage — Getting the Token Into AWS

    1. Terraform creates a secret resource in AWS Secrets Manager
         (empty shell — placeholder only)

    2. token manually injected via AWS Console or CLI after bootstrap
         captured from bootstrap run output
         this is the ONLY manual step — everything else is automated

the token lives in Secrets Manager. it never touches GitHub secrets
storage. fetched at runtime, masked immediately, used for the workflow
duration, then gone.


### The Workflow Signal — What Happens at Runtime

    workflow triggered (push to env branch)
      |
      +-- configure-aws-credentials action requests JWT from
      |     GitHub OIDC service internally
      |     JWT contains signed claims:
      |       repo, branch, actor
      |       audience: sts.amazonaws.com
      |       issuer: token.actions.githubusercontent.com
      |     JWT never appears in standard logs — only visible in
      |     debug mode (ACTIONS_STEP_DEBUG=true), requires write access
      |
      +-- JWT + target role ARN sent to AWS STS
      |     (AssumeRoleWithWebIdentity)
      |
      +-- AWS runs 4 checks — all must pass, one fails = whole thing fails:
      |     1. is token.actions.githubusercontent.com a registered OIDC
      |        provider in this account?
      |     2. is the audience (sts.amazonaws.com) in the provider's
      |        allowed client list?
      |     3. does the sub claim match the role's condition —
      |        correct account, repo, and branch?
      |     4. is the JWT signature valid — verified against
      |        GitHub's public key?
      |
      +-- all 4 pass → STS returns 3 temporary credentials (1 hour, no auto-renew):
      |
      |     AWS_ACCESS_KEY_ID      → identifies who is making the request
      |     AWS_SECRET_ACCESS_KEY  → signs every API request (HMAC-SHA256)
      |     AWS_SESSION_TOKEN      → proves these are temporary STS creds,
      |                               not permanent keys
      |
      +-- all 3 injected as masked env vars in runner
            + written to $GITHUB_ENV temp file on disk
            (the Actions runner writes env vars to disk as part of
            how it passes state between steps)

    credential security:
      - JWT is a bearer token. if grabbed within its ~5 minute validity
        window, it's usable from anywhere. BUT the claims can't be
        modified (e.g. change the branch) — the signature would break.
      - temp creds are also usable from anywhere until expiry. no IP
        binding. everything is logged in CloudTrail.
      - on a local runner: creds exist as process env vars AND in the
        $GITHUB_ENV temp file on disk. on a GH-hosted runner: VM is
        ephemeral and wiped after the job.
      - in practice: JWT is short-lived enough that theft is impractical.
        credential theft requires compromising the runner itself.


### Proxmox Token Fetch — Second Secret in the Same Workflow

    after AWS credentials are active:
      |
      +-- aws secretsmanager get-secret-value
      |     fetches JSON blob containing Proxmox token_id and token_secret
      |     (no Terraform involved here — pure AWS CLI)
      |
      +-- ::add-mask:: applied immediately on the raw blob
      |
      +-- JSON parsed → token_id and token_secret extracted
      |
      +-- 4 mask variations to cover any way the value could appear in logs:
      |     1. raw JSON blob
      |     2. token_id alone
      |     3. token_secret alone
      |     4. combined format (token_id=token_secret)
      |
      +-- written to $GITHUB_ENV:
      |     TF_VAR_proxmox_api_token=<token_id>=<token_secret>
      |
      +-- TF_VAR_ prefix is Terraform convention
            Terraform reads it automatically from env — no export needed
            uses it in the provider block to authenticate Proxmox API calls

    the token is a provider configuration variable — NOT a resource
    Terraform creates. so it does NOT appear in the Terraform state file.
    state records what was created, not what credential was used to create it.


### AWS Auth vs Proxmox Auth — Side by Side

                    AWS                         Proxmox
    method:         OIDC → STS temp creds       permanent API token
    lifetime:       ~1 hour                     never expires (--expire 0)
    how TF authn:   env vars from OIDC action   TF_VAR_ from Secrets Manager
    revocation:     auto-expires                manual: pveum user token remove
    where secret:   nowhere — generated on-fly  AWS Secrets Manager
    in TF state:    no (env vars)               no (provider config)


### Authorization — Per API Call, Not at the Door

authorization is NOT pre-checked at assume time. the OIDC handshake
confirms identity and issues credentials — it does not validate what
those credentials are allowed to do.

every single AWS API call Terraform makes (during plan or apply)
is independently evaluated by IAM in real time against the attached
policies. if Terraform tries to do something the role isn't allowed
to do — whether listing resources in plan or creating them in apply —
that specific API call fails at that moment.

the mental model: the handshake is passport control. confirms who you
are, lets you in. but every door inside still checks you individually.


### Terraform State and Locking

    terraform plan:
      +-- reads TF_VAR_* from env automatically
      +-- sends API calls → IAM authorizes each one
      +-- saves plan output to file
      +-- 3 minute delay safety window for plan review

    terraform apply:
      +-- sends API calls authorized against target resources
      +-- state written incrementally after each successful resource
            (not all at end — each resource writes immediately)
      +-- DynamoDB lock held for entire apply duration
      +-- deploys on Proxmox via API token


### Token Expiry and Long Apply Risk

temp credentials are issued once at workflow start — 1 hour, no
auto-renew. if terraform apply runs longer than that:

    token expires mid-apply
      +-- current API call fails
      +-- state reflects last successful write
            (reality says resource exists, state knows about it
            up to that point)
      +-- DynamoDB lock stays held even after token expires
      +-- recovery: terraform force-unlock → terraform plan
            to check what drifted

not a real concern at current scale — applies finish well within an
hour. if it ever becomes a concern, role-duration-seconds on the
configure-aws-credentials action can push it up to 12h (configurable
on the role itself).


### Identified Gap — Token Separation

current design: the infra role (env branch) can fetch the bootstrap-level
Proxmox admin token from Secrets Manager. this means the operational
workflow has access to the full-admin Proxmox token.

better pattern: restrict the Secrets Manager secret via resource policy
to TerraformAdmin role ARN only. effect:

    bootstrap token → accessible only from security branch
    infra role → gets only scoped operational tokens

matches the AWS 2-tier pattern exactly — high privilege gated behind
the secure branch.

not implemented — complexity overhead for current phase.
planned alongside:
  - import existing k8s_admin user under TF management
  - create remediation user via TF from scratch
  - update HashiCorp Vault secret with new token
  - scoped user tokens saved in TF state (acceptable since
    they are scoped, not bootstrap-level)


### Remediation User — Current State

the remediation pod user and token were created manually during early
setup, not via Terraform. at the time, the Proxmox users TF module
didn't exist. token stored directly in Vault, pod fetches at runtime.

planned TF-managed approach:

    TF creates user (remediation@pve)
      +-- TF creates token (marked sensitive, not printed)
      +-- token value in encrypted S3 state
      +-- pushed to Vault
      +-- pod fetches from Vault at runtime

same approach for importing the existing k8s-pve user. both deferred,
both have a clear path.


### Known Gaps

1. privilege escalation from TerraformAdmin
     admin can create roles without boundary → can exceed its own
     restrictions indirectly. intentional — branch is the gate.

2. temp credentials on local runner
     exist as process env vars AND $GITHUB_ENV file on disk during
     the job. on hosted runner: ephemeral VM wiped. on local runner:
     different threat model. accepted for solo project.

3. JWT visible in debug logs
     ACTIONS_STEP_DEBUG=true prints JWT in runner output. debug logs
     require write access to view. risk: accidentally left enabled →
     anyone with write access sees JWT for its ~5 minute window.
     mitigation: don't leave debug enabled permanently.

4. PassRole to EC2
     infra role has iam:PassRole for wireguard-ssm-role. if someone
     can modify TF config on the env branch, they could theoretically
     pass a different role to EC2. constrained by branch protection
     and ARN scoping.

5. permanent Proxmox API token
     never expires, full admin scope. if compromised, manual
     revocation required. PVE realm prevents OS-level pivot.
     rotation and scoped tokens are the future direction.

6. manually created users not under Terraform
     remediation user and k8s-pve user were created manually.
     no TF drift detection. documented plan to bring under TF.
