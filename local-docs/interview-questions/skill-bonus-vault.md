BONUS Skill — HashiCorp Vault (6 questions)
=============================================

Format: Standard questions only. Project examples are ammunition.
Your KMS auto-unseal chain, vault.env plaintext credentials tradeoff,
5 recovery keys, FreeIPA TLS via certmonger, AWS secrets engine for
etcd-backup, K8s TokenReview auth, Golang template rendering, Raft
quorum loss rebuild — inject when the bridge is earned.

---

1. What is HashiCorp Vault and why use it over simpler secret storage?

   Coverage check:
   - centralized secret management with access control
   - vs environment variables (no audit, no rotation, no access control)
   - vs Secrets Manager (Vault is multi-cloud, has more auth methods)
   - audit logging (every access recorded)
   - lease-based secrets (auto-expire, auto-revoke)
   - policy-based access (path-based, capabilities: create/read/update/delete/list)
   - HA deployment (Raft integrated storage vs Consul backend)
   - namespaces (Enterprise feature)

2. How does the unseal process work — and what is auto-unseal?

   Coverage check:
   - Vault starts sealed — encrypted data on disk, can't serve requests
   - Shamir's Secret Sharing — master key split into N shares, threshold K to unseal
   - unseal process: provide K shares → reconstruct master key → decrypt encryption key
   - auto-unseal with KMS (AWS, Azure, GCP, Transit)
   - KMS auto-unseal flow: Vault starts → calls KMS to decrypt master key → auto-unseals
   - recovery keys (for auto-unseal) vs unseal keys (for Shamir)
   - when you'd use recovery keys (generate new root token, rekey)
   - operational advantage of auto-unseal (restart without human intervention)

3. Explain Vault's encryption architecture — master key, encryption key, secrets.

   Coverage check:
   - three layers:
     1. KMS key encrypts master key (at rest on disk or in KMS)
     2. master key encrypts encryption key (barrier key)
     3. encryption key encrypts all secrets in storage
   - why three layers (separation of concerns, key rotation at each level)
   - barrier — everything past the barrier is encrypted
   - key rotation: rotate encryption key without re-encrypting all secrets
   - TLS on top (fourth layer — network encryption, separate from storage encryption)
   - transit engine (encryption-as-a-service for applications)

4. What auth methods does Vault support? How does LDAP auth work?

   Coverage check:
   - Token auth (root token, child tokens, orphan tokens)
   - token types: service tokens (renewable, heavy) vs batch tokens (lightweight, no renewal)
   - TTL, max TTL, token renewal
   - AppRole (machine auth — role_id + secret_id)
   - Kubernetes auth (ServiceAccount → TokenReview API → Vault role)
   - LDAP auth (bind to LDAP server, map LDAP groups to Vault policies)
   - OIDC auth
   - how Vault maps auth identity → policy → secret access

5. What are dynamic secrets and how do they differ from static secrets?

   Coverage check:
   - static: stored value, manual rotation, long-lived
   - dynamic: generated on demand, unique per consumer, auto-expire
   - AWS secrets engine (generate temporary IAM credentials via STS)
   - database secrets engine (create/revoke DB users per request)
   - PKI secrets engine (issue certificates on demand)
   - KV engine v1 vs v2 (v2 has versioning, soft delete, metadata)
   - lease management (TTL, renewal, revocation)
   - blast radius reduction (each consumer gets unique credentials)

6. How do you inject Vault secrets into Kubernetes pods?

   Coverage check:
   - Vault Agent Injector (mutating webhook approach):
     - vault-agent-init container (authenticate, fetch secrets)
     - vault-agent sidecar (keep secrets refreshed)
     - annotations on pod spec to configure injection
     - template rendering (Golang templates for config files)
   - CSI driver (mount secrets as volumes, no sidecar needed)
   - external-secrets operator (sync Vault secrets to K8s Secrets)
   - K8s auth method requirements:
     - Vault needs: K8s API URL, CA cert, ServiceAccount token for TokenReview
     - Pod needs: ServiceAccount with bound role in Vault
   - what happens when injector is down during pod creation (silent failure)
   - response wrapping for sensitive injection
