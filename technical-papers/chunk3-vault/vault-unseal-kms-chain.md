Vault Cluster Operations — TLS, KMS Unseal, and Human Auth (Summary Trace)
=============================================================================

pre-trace (one-time setup):
  TF creates vault-unseal IAM user (no IAM policy) + access key + secret key
    → TF creates KMS key (alias/vault-unseal) with 3-tier key policy:
      root=fallback, admins=lifecycle only, vault-unseal=encrypt/decrypt only
    → TF stores IAM credentials into Secrets Manager (same module/state)
  FreeIPA service principals registered per vault node (vault/hostname)
  vault operator init → generated master key → encrypted via KMS → stored in Raft
    → 5 recovery keys → Secrets Manager (emergency fallback)

--- chain 1: TLS certs from FreeIPA CA ---

vault node joins FreeIPA domain → receives /etc/ipa/ca.crt (CA trust anchor)
  → Ansible runs ipa-getcert request -K vault/vault1.lab.local
    → FreeIPA checks service principal exists + correct host → signs cert
      → tls.crt (public) + tls.key (private, chmod 600 vault user)
        → certmonger registered for auto-renewal

→ vault2 connects to vault1 (Raft)
  → vault1 presents tls.crt → vault2 verifies against /etc/ipa/ca.crt (local, no FreeIPA contact)
    → challenge-response with public/private key → mutual trust → encrypted connection

→ cert approaching expiry → certmonger contacts FreeIPA CA → renewed cert
  → post-renewal hook: systemctl reload vault → new cert picked up, no downtime

--- chain 2: KMS auto-unseal on every restart ---

vault workflow triggers → GH workflow fetches vault-unseal IAM creds from Secrets Manager
  → writes to $GITHUB_ENV → resolves into real values for SSH command

→ SSH to ansible node: export VAULT_UNSEAL_ACCESS_KEY='...' && ansible-playbook ...
  → Ansible lookup('env') reads from shell → vault_aws_access_key_id
    → template vault.env.j2 renders into /etc/vault.d/vault.env on each vault node
      → when condition: both vars defined + length > 0 (prevents empty-value wipe)
        → no_log: true (prevents key appearing in GH Actions log)

→ vault service starts → reads vault.env → loads AWS credentials
  → reads vault.hcl → finds seal "awskms" { kms_key_id = "alias/vault-unseal" }
    → reads encrypted master key blob from Raft storage

→ DNS: Vault resolves kms.eu-central-1.amazonaws.com
  → FreeIPA (lab.local only) → forwards to 8.8.8.8 → returns KMS IP
    → FreeIPA MUST be up before Vault — no DNS = no KMS = no unseal

→ Vault signs request with secret key locally (SigV4 HMAC-SHA256)
  → secret key NEVER sent over wire — only access key ID + signature
    → signature timestamped, expires in minutes, not replayable

→ HTTPS POST to KMS endpoint (TLS encrypted, public internet path)
  → network: Vault LXC → VLAN → MikroTik → ISP → AWS KMS
    → NOT through WireGuard (that's private VPC traffic)
    → packet capture sees TLS ciphertext only — headers/body/keys all encrypted

→ KMS receives authenticated request
  → checks key policy: vault-unseal in "use" statement? YES
    → KMS decrypts using hardware-bound key (never leaves HSM)
      → returns plaintext master key in TLS-encrypted response

→ Vault receives plaintext master key (held in memory only, never on disk)
  → master key decrypts the encryption key (also in memory only)
    → Vault is UNSEALED — barrier open, can now decrypt secrets on demand
      → secrets NOT decrypted at this point — only when clients request them
        → loads auth backends (LDAP config) → serving API requests
          → no human intervention, fully automatic on every restart

→ bootstrap security tradeoff:
  AWS credentials in vault.env are STATIC (access key + secret key in a file)
    → can't use Vault to manage credentials that unseal Vault (circular)
      → secured by: file permissions (vault user only) + TLS + SigV4 + KMS key policy

--- chain 3: human operator auth via FreeIPA LDAP ---

operator enters vault_operator + password in Vault UI/CLI
  → Vault LDAP backend sends BIND to FreeIPA (port 636 LDAPS)
    → FreeIPA validates password → queries group membership → returns: vault-admins

→ Vault checks local mapping: vault-admins → policies=super_admin
  → issues token with super_admin policy → operator authenticated and authorized
