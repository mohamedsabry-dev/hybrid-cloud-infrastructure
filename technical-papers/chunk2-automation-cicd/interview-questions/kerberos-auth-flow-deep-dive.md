Kerberos Authentication Flow — TGT, Service Tickets, HBAC, and Sudo Authorization
====================================================================================

Question:
  Walk me through what happens after kinit. How does Kerberos
  authenticate a user to a target host? What's the difference between
  authentication and authorization here? What role does SSSD play?

---

Three layers — authentication, then two authorization checks:

  Authentication: "who are you?" → Kerberos (TGT → service ticket)
  Authorization 1: "can you SSH here?" → HBAC rules via SSSD
  Authorization 2: "can you sudo?" → Sudo rules via SSSD

  All three managed centrally in FreeIPA. Failing any one = blocked.

---

Phase 1 — kinit (already done, covered in ansible-workflow-kerberos-auth.md):

  kinit -kt keytab super_bot@LAB.LOCAL
    → keytab contains derived keys (not password itself)
      → presents proof of identity to FreeIPA KDC
        → KDC issues TGT: "super_bot authenticated at 14:30, valid until 02:30"
          → TGT encrypted with KDC's own key (nobody can forge it)
            → stored in ticket cache (memory on ansible node)

---

Phase 2 — getting a service ticket (ansible node → KDC):

  Ansible runs: ssh super_bot@worker1.lab.local
    → SSH client sees GSSAPI configured → needs service ticket for target

  ansible node → KDC:
    "I'm super_bot (here's my TGT), I need a ticket for host/worker1.lab.local"

  KDC:
    → decrypts TGT with its own key → valid, not expired, it's super_bot
    → creates service ticket:
        content: "super_bot is authenticated, valid until X"
        encrypted with WORKER1's host key (only worker1 can read this)
    → also creates a session key, encrypted with super_bot's key

  KDC → ansible node:
    → service ticket + session key returned

  At this point ansible node has a ticket that only worker1 can open.
  KDC's job is done — it won't be contacted again for this connection.

---

Phase 3 — presenting the service ticket (ansible node → target):

  ansible node → worker1:
    → SSH sends service ticket via GSSAPI

  worker1:
    → has its own host keytab (created when it joined FreeIPA domain)
    → decrypts service ticket with its host key
    → inside: "KDC says this is super_bot, authenticated, valid"
    → trusts this because ONLY the KDC could have encrypted it
      with worker1's key — if the ticket decrypts cleanly, KDC made it

  AUTHENTICATION: PASSED — worker1 knows WHO is connecting

  Critical detail: worker1 does NOT contact the KDC to verify.
  It decrypts locally with its own key. That's why Kerberos scales —
  KDC is only involved when ISSUING tickets, not when VERIFYING them.

---

Phase 4 — HBAC check (authorization layer 1: can you SSH here?):

  Authentication passed, but that doesn't mean access is allowed.

  SSSD on worker1:
    → "super_bot wants SSH access to this host"
    → queries FreeIPA LDAP for HBAC (Host-Based Access Control) rules
    → looks for a rule matching:
        user = super_bot (or a group super_bot belongs to)
        host = worker1 (or hostgroup containing worker1)
        service = sshd

  Rule found → SSH GRANTED
  No rule → ACCESS DENIED (even though Kerberos authentication passed)

  This is the distinction:
    Kerberos says "this IS super_bot" (authentication)
    HBAC says "super_bot is ALLOWED on this host" (authorization)
    You can be authenticated and still denied — different decisions.

---

Phase 5 — sudo check (authorization layer 2: can you escalate?):

  Ansible task has become: yes → needs root privileges

  sudo on worker1:
    → asks SSSD: "can super_bot run commands as root?"
    → SSSD checks cached sudo rules from FreeIPA:
        super_bot → ALL commands → NOPASSWD
    → ALLOW → task runs as root

  Sudo rules cached by SSSD (don't query FreeIPA live every time).
  HBAC rules checked live on each SSH connection.

---

What each host needs to participate:

  Target node must have:
    → SSSD installed and configured (talks to FreeIPA)
    → Joined to FreeIPA domain (ipa-client-install)
    → Host keytab at /etc/krb5.keytab (created during domain join)
    → SSH configured for GSSAPI authentication

  If SSSD is down on target:
    → HBAC can't be checked → SSH denied (fail-closed)
    → sudo rules can't be resolved → escalation denied

  If FreeIPA is down:
    → KDC unreachable → can't get NEW service tickets
    → existing cached tickets still work until they expire
    → SSSD has cached HBAC/sudo rules → may still work briefly
    → extended outage → everything fails

---

Three independent kill switches (all in FreeIPA):

  1. Delete keytab from Secrets Manager → can't get TGT → can't start
  2. Remove HBAC rule → can authenticate but can't SSH to any host
  3. Remove sudo rule → can SSH but can't escalate to root

  Revoking any one blocks the pipeline. All managed centrally —
  don't need to touch individual target nodes.

---

Why the target never contacts KDC:

  The trust model is built on encryption, not live verification:
    → KDC encrypted the service ticket with worker1's key
    → only worker1 has that key (from its host keytab)
    → if worker1 can decrypt it → KDC must have made it → trusted

  This is what makes Kerberos different from something like LDAP bind
  where every authentication requires a live call to the directory.
  Kerberos front-loads the trust into encrypted tickets.

  Trade-off: if you revoke super_bot in FreeIPA, existing tickets
  still work until expiry (default 24h). HBAC catches this because
  it checks live — but the Kerberos layer alone wouldn't know.

---

Related:
  ansible-workflow-kerberos-auth.md — full pipeline workflow
  vault-unseal-kms-chain.md chain 3 — LDAP auth (different: BIND, not Kerberos)
