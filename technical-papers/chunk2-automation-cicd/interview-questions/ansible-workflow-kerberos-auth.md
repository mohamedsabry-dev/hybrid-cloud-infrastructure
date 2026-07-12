Ansible Workflow — Kerberos Auth, Keytab, Vault Secrets, and Full Deployment Chain
====================================================================================

Question:
  Explain how Ansible works in your environment. How does it
  authenticate to target nodes? What's a keytab? What's a Kerberos
  ticket? How do secrets flow through the pipeline?

---

The full workflow end-to-end:

  Developer pushes to env branch (dev or prod)
    → GitHub Actions workflow triggers on self-hosted runner LXC (10.0.63.20)

  Step 1 — OIDC + AWS credentials:
    → runner sends GitHub JWT to AWS STS → receives temporary credentials
      → these are short-lived (1 hour), scoped to specific role
        → no static AWS keys stored in GitHub

  Step 2 — fetch keytab from Secrets Manager:
    → aws secretsmanager get-secret-value --secret-id {env}/super_bot/keytab
      → keytab stored as base64 string → decode → write /tmp/super_bot.keytab on runner
        → pipe keytab binary over SSH to ansible node (10.0.63.10) → lands as /tmp/kt

  Step 3 — Kerberos authentication:
    → on ansible node: kinit -kt /tmp/kt super_bot@LAB.LOCAL
      → kinit reads keytab → presents to FreeIPA KDC → KDC issues TGT
        → TGT stored in ticket cache (memory)
          → delete /tmp/kt from ansible node
          → delete /tmp/super_bot.keytab from runner
            → keytab existed on disk for seconds only

  Step 4 — fetch runtime secrets + vault password:
    → runner fetches runtime vars from Secrets Manager (env-specific)
      → mask → write to $GITHUB_ENV (available in workflow steps)
    → for ansible-full-setup: also fetches {env}/ansible/vault-password
      → SSHes to ansible node → writes to ~/.ansible_vault (chmod 600)

  Step 5 — prepare code:
    → runner SSHes to ansible node
      → export runtime vars into SSH session
        → GITHUB_ENV not visible over SSH — must explicitly export
      → cd /srv/repo && git pull origin {env} → gets latest code
      → cd ansible/{env}

  Step 6 — run playbook:
    → ansible-playbook -i inventory/inventory.ini playbook.yml
      → inventory has FQDNs, all using super_bot as ansible_user
      → per target node:
        → Ansible connects via SSH with Kerberos (GSSAPI)
          → presents TGT to KDC → KDC issues service ticket for target host
            → target's SSSD checks HBAC rules live → SSH allowed
              → sudo rules from SSSD cache → passwordless for super_bot

  Step 7 — secrets during playbook execution:
    Two types of secrets in play:

    a) Ansible Vault encrypted vars (in group_vars files):
      → variables like ldap_bindpass, emergency_password stored as:
        !vault | $ANSIBLE_VAULT;1.1;AES256 ... (encrypted inline in YAML)
      → ansible.cfg: vault_password_file = ~/.ansible_vault
        → Ansible reads password from that file → decrypts vars at runtime
        → the password file lives on ansible node only, chmod 600, root-owned

    b) AWS-sourced runtime secrets (from step 4):
      → injected as env vars via export over SSH session
        → available to playbook tasks as lookup('env', 'VAR_NAME')
        → example: Vault unseal credentials passed this way

  Step 8 — cleanup (always, even on failure):
    → kdestroy on ansible node → TGT destroyed
    → SSH session closes → exported env vars gone from ansible OS
    → keytab files already deleted in step 3

---

What is a keytab:

  NOT "encrypted password." It's cryptographic keys DERIVED from the
  password using a key derivation function (string2key → AES256 keys).

  When you create super_bot's keytab on FreeIPA:
    password → string2key → AES256 encryption key → stored in keytab file

  kinit -kt keytab = "authenticate using this key directly"
    (instead of kinit + type password → derive key → authenticate)

  Having the keytab = having the password. Anyone with the keytab file
  can authenticate as that user. That's why:
    - Stored in AWS Secrets Manager (encrypted at rest)
    - Exists on disk for seconds during workflow
    - Deleted immediately after kinit
    - Never logged (masked in GitHub Actions)

---

What is a Kerberos ticket (TGT):

  Three-step authentication:

  1. kinit (client → KDC):
    "I'm super_bot, here's proof I know my key" (from keytab)
    → KDC verifies → creates TGT (Ticket Granting Ticket)
    → TGT = signed blob: "super_bot authenticated at 14:30, valid until 02:30"
    → stored in memory (ticket cache). Keytab no longer needed.

  2. SSH to target (client → KDC → target):
    "I have this TGT, I need to reach worker1.lab.local"
    → KDC checks TGT → creates service ticket for worker1
      → encrypted with worker1's own key (only worker1 can read it)
    → client presents service ticket to worker1
    → worker1 decrypts → "KDC vouches for super_bot, access granted"

  3. The point:
    Password/keytab used ONCE to get the TGT.
    TGT used to get service tickets for each target host.
    Password never crosses the network after kinit.

  Analogy:
    Keytab = passport (permanent identity, locked in a safe)
    TGT = airport security wristband (temporary, proves you passed check)
    Service ticket = boarding pass (one per flight/destination)
    kdestroy = cut the wristband, need security again

---

Why two separate nodes (runner vs ansible):

  Runner LXC = GitHub-facing. Receives workflow triggers, has internet
    access for OIDC + Secrets Manager. Doesn't run playbooks.

  Ansible LXC = execution environment. Has the repo, keytab auth,
    vault password, Kerberos ticket. Runs playbooks against fleet.

  Separation: runner doesn't need fleet access. Ansible node doesn't
  need GitHub/internet access. Compromise one, the other is clean.

---

Why super_bot not root:

  super_bot is a FreeIPA domain user with:
    - HBAC rules controlling which hosts it can access
    - Sudo rules for passwordless privilege escalation
    - Kerberos authentication (no SSH password)
    - Auditable (FreeIPA logs every TGT + service ticket)

  Root has no FreeIPA integration. No HBAC. No audit trail.
  super_bot gives you centralized access control — revoke in FreeIPA,
  locked out of entire fleet instantly.

---

Related:
  OIDC trust chain: see oidc-terraform-trust-chain.md
  Vault unseal credentials flow: see vault-unseal-kms-chain.md (chain 2)
  Keytab generation guide: ansible/{env}/playbooks/freeipa/generate_keytab_guide.txt
