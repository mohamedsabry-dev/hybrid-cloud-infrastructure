Skill 16 — Identity / Directory Services — FreeIPA (8 questions)
=================================================================

Format: Standard questions only. Project examples are ammunition.
Your Vault LDAP auth, three separate PKIs, VIP SAN cert fix, circular
FreeIPA dependency break, passwordless sudo for bots, LXC UID keyring
fix, SSSD cache timing, keytab pipeline — inject when the bridge is earned.

---

1. What is a directory service and what problem does it solve?

   Coverage check:
   - centralized identity management (users, groups, hosts, policies)
   - LDAP structure (DN, OU, CN, DC, base DN)
   - LDAP bind types (simple, SASL)
   - FreeIPA components (389 Directory Server, MIT Kerberos, Dogtag CA, SSSD)
   - FreeIPA vs Active Directory (Linux-native vs Windows-native)
   - AD trust / integration (cross-realm, when you'd need both)
   - replication and multi-master topology

2. What is the difference between authentication and authorization?

   Coverage check:
   - authentication: proving who you are (password, certificate, keytab, token)
   - authorization: what you're allowed to do (RBAC, HBAC, sudo rules, policies)
   - how they chain: authenticate first, then check authorization
   - examples of each failing independently
   - how directory services provide both

3. How does Kerberos work — TGT, service tickets, keytabs?

   Coverage check:
   - Kerberos flow:
     AS-REQ → KDC → AS-REP (TGT issued)
     TGS-REQ (with TGT) → KDC → TGS-REP (service ticket issued)
     AP-REQ (with service ticket) → target service
   - TGT (Ticket Granting Ticket) — proves identity, reusable
   - service ticket — proves authorization to specific service
   - keytab: file containing service/host key, used for passwordless auth
   - keytab vs password (automation vs human)
   - SSO (Single Sign-On) — one TGT, access many services without re-authenticating
   - service principals (SPN) — host/fqdn@REALM, HTTP/fqdn@REALM
   - why Kerberos requires FQDNs (not IPs) — reverse DNS lookup for SPN matching
   - ticket lifetime and renewal

4. How do you control who can access which hosts and with what privileges?

   Coverage check:
   - HBAC (Host-Based Access Control) — which users can access which hosts
   - sudo rules (centralized sudo policy, who can run what as whom)
   - HBAC + sudo together (HBAC gates SSH access, sudo gates privilege)
   - password policies (per-group, different for automation vs human)
   - user groups, host groups (policy targets)
   - service accounts vs human accounts (different policies)

5. What is SSSD and what does it do on the client side?

   Coverage check:
   - System Security Services Daemon — local caching for identity/auth
   - caches user info, group membership, sudo rules
   - offline login (cached credentials when server unreachable)
   - cache invalidation and refresh intervals (~15 min for sudo)
   - how fast can you force immediate revocation
   - SSSD vs direct LDAP/Kerberos queries (performance, resilience)
   - what breaks when FreeIPA is down (new logins fail, cached sessions survive)
   - user deletion propagation timing

6. How do you join a Linux machine to a domain?

   Coverage check:
   - ipa-client-install / realm join (automated enrollment)
   - what it configures (SSSD, Kerberos, DNS, NTP)
   - OTP-based enrollment for automation
   - DNS integration (why FreeIPA runs its own DNS)
   - NTP requirement (Kerberos is time-sensitive)
   - LXC container enrollment differences (UID mapping, keyring issues)
   - unenrolling and re-enrolling

7. How does certificate management work in an identity system?

   Coverage check:
   - FreeIPA as a CA (Dogtag)
   - certmonger (automatic certificate request and renewal)
   - certificate lifecycle (request, issue, renew, revoke)
   - SAN (Subject Alternative Name) — adding extra hostnames to a cert
   - service certificates vs host certificates
   - CA trust hierarchy
   - multiple PKIs in one environment (FreeIPA CA, K8s CA, etcd CA — separate trust domains)

8. A user can authenticate but can't SSH to a specific host. What do you check?

   Coverage check:
   - HBAC rules (does the user have access to this host?)
   - is the HBAC rule applied to the right user group and host group?
   - SSSD cache (has the rule propagated? sss_cache -E to force)
   - SSH service enabled in HBAC rule (not just login)
   - PAM configuration (pam_sss properly configured?)
   - check from server side (journalctl -u sshd, /var/log/secure)
   - Kerberos ticket validity (klist, kinit)
   - DNS (does the hostname resolve correctly for Kerberos SPN?)
