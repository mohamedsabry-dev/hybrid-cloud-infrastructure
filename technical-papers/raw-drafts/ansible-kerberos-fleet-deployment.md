Ansible Fleet Deployment — From GitHub to Kerberos to Node
===========================================================

Traces how a GitHub Actions workflow reaches the on-prem Ansible
node, authenticates via Kerberos keytab, and deploys to a
FreeIPA-managed fleet. Covers the two-phase transition (pre-domain
to post-domain), FreeIPA's access control model, SSSD caching,
and the secret injection paths.


### Architecture — Why Runner and Ansible Are Separate

    GitHub → mac-mini (TF) → dev-local-runner (10.0.63.20) → ansible node (10.0.63.10) → fleet

runner and ansible are separate LXCs — intentional separation:

    runner (GH-facing surface)
      +-- executes workflow YAML
      +-- SSHes to ansible node — nothing more
      +-- runs as unprivileged "runner" user
      +-- if compromised: cannot read ansible's local files,
      |   can only reach ansible via SSH
      +-- can be rebuilt and re-registered without touching ansible

    ansible node (execution environment)
      +-- holds the repo (/srv/repo)
      +-- holds vault password file
      +-- holds deploy key + Galaxy collections
      +-- runs as root
      +-- the only place playbooks execute

    runner SSH to ansible: during runner setup, root's SSH key pair
    is copied to the runner user. runner SSHes to ansible using
    root's key even though the service runs as the runner user.


### FreeIPA Identity — The 3 Layers

a domain controller. all compute nodes are added to it so they
trust it as the authority. creating users and groups alone does
nothing — no access is granted until rules are created on top.

three completely separate systems, not a single policy document:

    Layer 1 — HBAC (Host-Based Access Control) = the door
      +-- can this user SSH to this machine? yes or no, nothing else
      +-- k8s_admin has HBAC rule for k8s_masters → can SSH in
      +-- no HBAC rule for vault nodes → SSH rejected at PAM level
      |   before even asking for a password
      +-- this is authentication — getting through the door

    Layer 2 — Sudo Rules = what you can do after you're in
      +-- no sudo rule = stuck as regular Linux user
      +-- can read world-readable files, run non-root commands
      +-- cannot touch system config, restart services, install packages
      +-- super_bot has !authenticate flag → passwordless sudo
      |   on automation_group nodes
      +-- k8s_admin has sudo WITH password prompt on k8s nodes
      +-- this is authorization — what you're allowed to do inside

    Layer 3 — IPA Roles = can this user manage FreeIPA itself
      +-- create users, reset passwords, modify DNS
      +-- not relevant to this setup — only admin manages IPA
      +-- admin is hardcoded as superuser (like root on Linux —
          root doesn't need to be in sudoers, it just IS root)


### The Mental Model Difference From AWS

    AWS = deny all by default
      +-- new user can do nothing
      +-- you build UP from zero

    Linux/FreeIPA = allow all by default for logged-in users
      +-- you fence DOWN
      +-- any user who gets through the door (HBAC) is immediately
      |   a regular Linux user
      +-- can run any non-root command, read world-readable files,
      |   write to /tmp and home directory
      +-- the fencing: HBAC controls which machines they reach,
          sudo rules control what they can do as root

    if you need to restrict even non-root commands (e.g. monitoring
    user limited to ps and top), the option is rbash (restricted
    bash) — can't cd, can't change PATH, can't run commands with /,
    can't redirect output. set shell to /bin/rbash and control PATH.

    in practice rarely done because "no sudo + HBAC scoping" is
    sufficient. the dangerous operations (shutdown, reboot, ip link
    set, nmcli modify) already require root — no sudo rule means
    they can't run them anyway.


### Phase 1 — Before Domain: Bootstrap Access

before FreeIPA exists, Ansible uses the first-setup inventory:

    first_setup_inventory.ini
      +-- targets nodes by IP (no DNS yet)
      +-- authenticates as root user
      +-- all nodes built from golden image:
      |     Python and IPA client pre-installed
      +-- TF injects ansible SSH public key into each new VM/LXC
          at creation time

    execution pattern:
      runner SSHes to ansible node
        +-- cd /srv/repo && git pull origin env
        +-- cd ansible/env
        +-- ansible-playbook -i inventory/first_setup_inventory.ini <playbook>

no domain, no Kerberos — plain root SSH to everything.


### Phase 2 — After Domain: FreeIPA Controls Access

all compute nodes added to FreeIPA domain. domain provides:
DNS, NTP (VMs only — LXCs share kernel clock), HBAC, sudo rules,
LDAP auth.

    admin users created per host group:
      +-- HBAC: SSH access to their host group only
      +-- sudo: with password required
      +-- auth: LDAP with password

    super_bot = automation user:
      +-- HBAC: all host groups EXCEPT FreeIPA node itself
      +-- sudo: passwordless (!authenticate) across all host groups
      |   except IPA
      +-- auth: password (manual) + keytab (automation)

    post-domain execution pattern:
      +-- inventory switches to inventory.ini
      +-- nodes referenced by FQDN, not IP
      +-- user is super_bot, not root
      +-- authentication is Kerberos TGT from keytab


### The Keytab — What It Is and How It Works

a keytab is a binary file containing pre-computed Kerberos
encryption keys derived from the password. it is NOT an encoded
password — it's the derived keys themselves, pre-computed.

allows passwordless Kerberos authentication without prompts.
this is what makes automation possible — kinit reads the keytab
instead of waiting for a password prompt.

    if password changes → existing keytab invalid
      +-- must regenerate keytab
      +-- must update the base64 string in AWS Secrets Manager

    two generation methods:
      Method 1 (no -r): generates NEW random keys
        +-- keytab works for Kerberos auth
        +-- password auth BROKEN (keys don't match password anymore)

      Method 2 (-r): retrieves existing keys derived from password
        +-- both keytab and password work (current approach)

    storage: keytab stored in AWS Secrets Manager as base64
    (binary → text for storage/transport)


### Keytab Runtime Flow — The Authentication Chain

    workflow starts (push to env branch)
      |
      +-- GH trust + authenticate AWS (same OIDC pattern as infra role)
      |
      +-- fetch keytab from Secrets Manager
      |     aws secretsmanager get-secret-value → base64 string
      |
      +-- base64 decode → write to /tmp/super_bot.keytab on runner
      |
      +-- pipe over SSH to ansible node
      |     the keytab binary lands on ansible node
      |
      +-- kinit immediately on ansible node
      |     reads keytab → presents to FreeIPA KDC
      |     KDC validates → issues TGT (Ticket Granting Ticket)
      |     TGT stored in Kerberos ticket cache in memory
      |
      +-- delete /tmp/kt from ansible node
      |
      +-- delete /tmp/super_bot.keytab from runner
      |
      +-- result: Kerberos TGT in memory on ansible node
            no keytab file persists anywhere after kinit


### SSSD — Cache Timing and Revocation Delays

SSSD (System Security Services Daemon) runs on every domain-joined
node. it does two different things at different times:

    at login (each SSH attempt):
      +-- validates password against FreeIPA live
      +-- checks HBAC against FreeIPA live
      +-- caches user info (UID, GID, groups, home dir)

    on a schedule (independent of logins):
      +-- pulls sudo rules from FreeIPA LDAP every ~15 minutes
      +-- full refresh every 6 hours

sudo rules are already cached on the node before anyone logs in.
when a user runs sudo, the system checks the local SSSD cache —
not FreeIPA in real time.

    what this means for revocation:

      sudo rule removed on IPA
        +-- node knows: ~15 min (SSSD refresh)
        +-- user keeps sudo until cache expires

      HBAC rule removed on IPA
        +-- node knows: next SSH attempt (checked live)
        +-- existing sessions stay alive

      password changed on IPA
        +-- node knows: immediately (checked live)
        +-- no session impact

      user deleted on IPA
        +-- node knows: ~15 min (SSSD refresh)
        +-- existing session stays until timeout

    to force immediate effect:
      sssctl cache-expire -E   or   systemctl restart sssd
      on each affected node — no automated mechanism for this


### Secret Injection During Playbook Runtime

two approaches depending on the secret's origin:

    Approach A — Ansible Vault (bootstrap-phase secrets)
      +-- ansible-vault encrypt_string → encrypted reference
      |   stored in group_vars
      +-- ansible.cfg points to ~/.ansible_vault password file
      |   on the ansible node
      +-- auto-decrypted at runtime — no manual step during playbook
      +-- the vault password file on ansible node is a high-value target

    Approach B — env lookup via AWS Secrets Manager (operational secrets)
      +-- fetch from AWS → mask → write to $GITHUB_ENV
      +-- in SSH run step: explicit export VAR='value' before
      |   the ansible-playbook command
      +-- required because $GITHUB_ENV is only known to the GH Actions
      |   runner — not to the ansible SSH session
      +-- after SSH session closes → exported vars gone from ansible OS
          no persistence, other users never see them


### The Full Signal Flow

    workflow triggered (push to env branch)
      |
      +-- GH trust + authenticate AWS (OIDC → assume infra role)
      |
      +-- fetch secrets from Secrets Manager:
      |     keytab (always) + runtime vars (if needed)
      |     mask → write to $GITHUB_ENV
      |
      +-- fetch keytab → decode → pipe to ansible node → kinit
      |     → delete keytab from both sides
      |     → TGT now in memory on ansible node
      |
      +-- SSH to ansible node
      |     +-- if runtime vars needed: explicit export commands
      |     |   before playbook call
      |     +-- git pull latest code from branch
      |     +-- ansible-playbook with inventory.ini (FQDN-based)
      |
      +-- ansible connects to fleet nodes
      |     +-- Kerberos TGT presented → SSSD on target validates
      |     +-- HBAC checked live → SSH allowed or rejected
      |     +-- sudo rules from SSSD cache → passwordless for super_bot
      |     +-- playbook tasks execute
      |
      +-- output flows: fleet → ansible → runner → GH logs
      |
      +-- final step (always()): kdestroy on ansible node
            destroys Kerberos ticket cache — TGT gone


### Known Gaps

1. keytab base64 not masked in workflow
     the keytab is piped directly over SSH so it doesn't appear in
     logs in practice. but the base64 string is not explicitly
     masked with ::add-mask:: — if the workflow changes and the
     value is echoed, it would be visible.

2. keytab in Secrets Manager is a high-value target
     if the secret is compromised, the attacker has the keytab which
     can generate Kerberos TGTs for super_bot — passwordless sudo
     on all automation nodes. keytab has no expiry unless the
     password is changed. mitigated by access controls on the secret
     (only the infra role can fetch it).

3. shared Kerberos ticket cache
     if workflow kdestroy runs while a manual session is active on
     the same ansible node (both root), the shared ticket cache is
     destroyed. active connections survive (already authenticated),
     new connections fail. low risk in solo setup.

4. SSSD 15-minute revocation window
     sudo rule changes have up to 15-minute propagation delay.
     in a real incident requiring immediate revocation, must manually
     run sssctl cache-expire -E on every affected node. no automated
     mechanism. accepted — solo setup, manual revocation sufficient.

5. no HBAC explicit deny rules
     FreeIPA HBAC is allow-only. no rule = denied by default. no
     mechanism for "explicitly deny this user this host." to remove
     access: remove user from the group or delete the rule.

6. ansible vault password file
     ~/.ansible_vault on the ansible node is persistent and
     unencrypted. if the ansible node is compromised, all
     Ansible Vault encrypted secrets are decryptable. same threat
     model as the keytab — node compromise = full access.
