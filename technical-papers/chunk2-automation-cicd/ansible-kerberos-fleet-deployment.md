Ansible Fleet Deployment — Full Signal Trace (Summary)
=======================================================

setup: runner LXC (10.0.63.20) and ansible LXC (10.0.63.10) are separate
  runner = GH-facing, ansible = execution environment with repo + vault password + keytab auth
  super_bot = FreeIPA domain user with HBAC + passwordless sudo across fleet

developer pushes to env branch
  → GitHub Actions picks up workflow on self-hosted runner LXC
    → configure-aws-credentials: GitHub JWT → AWS STS → temporary credentials (OIDC)

→ aws secretsmanager get-secret-value → fetches:
    → {env}/super_bot/keytab (base64-encoded keytab)
    → runtime vars (vault unseal creds, etc.)
    → {env}/ansible/vault-password (for ansible-full-setup workflows)
  → mask → write to $GITHUB_ENV

→ keytab flow (seconds on disk, then deleted):
  → base64 decode → write /tmp/super_bot.keytab on runner
    → pipe keytab binary over SSH to ansible node → lands as /tmp/kt
      → kinit -kt /tmp/kt super_bot@LAB.LOCAL → presents key to FreeIPA KDC
        → KDC verifies → issues TGT (Ticket Granting Ticket) → stored in ticket cache (memory)
          → delete /tmp/kt from ansible node → delete /tmp/super_bot.keytab from runner

→ vault password flow (ansible-full-setup only):
  → SSHes to ansible node → writes password to ~/.ansible_vault (chmod 600)
    → ansible.cfg: vault_password_file = ~/.ansible_vault
      → Ansible reads this file to decrypt !vault vars in group_vars at runtime

→ runner SSHes to ansible node (root's key)
  → export runtime vars into SSH session (GITHUB_ENV not visible over SSH)
    → cd /srv/repo && git pull origin env → cd ansible/env

→ ansible-playbook -i inventory/inventory.ini (FQDNs, super_bot user)
  → per target node:
    → TGT presented to KDC → KDC issues service ticket for target host
      → SSSD checks HBAC live → SSH allowed (GSSAPI auth)
        → sudo rules from SSSD cache → passwordless for super_bot
  → two types of secrets in play:
    → Ansible Vault: !vault encrypted vars in group_vars → decrypted via ~/.ansible_vault
    → AWS-sourced: runtime env vars injected via export over SSH session

→ output flows: fleet → ansible → runner → GitHub Actions logs
  → always(): kdestroy on ansible node → TGT destroyed
    → SSH session closes → exported env vars gone from ansible OS
