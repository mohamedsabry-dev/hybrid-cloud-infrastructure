Vault Cluster Operations — TLS, KMS Unseal, and Human Auth
============================================================

Traces three operational chains for the HashiCorp Vault cluster:
how nodes get their TLS certificates from FreeIPA CA, how Vault
auto-unseals via AWS KMS on every restart, and how human operators
authenticate via FreeIPA LDAP. Covers the bootstrap secret
injection path, a credential wipe incident, and the KMS key policy
separation.


### Ansible Vault — Bootstrap Phase Encryption

before HashiCorp Vault exists, secrets still need to reach
playbooks without being committed to Git. Ansible Vault is just
an encryption tool — not a secret store.

    ansible-vault encrypt_string → encrypted !vault block
      +-- block goes into group_vars files (committed to Git)
      +-- the password to decrypt lives in AWS Secrets Manager
      |     at {env}/ansible/vault-password
      +-- at runtime:
            workflow fetches vault password from Secrets Manager
            → writes to ~/.ansible_vault on ansible node
            → ansible.cfg points to that file path
            → Ansible loads group_vars → decrypts !vault blocks automatically


### How Secrets Get From GitHub Into Ansible

two methods depending on phase:

    lookup('env', 'VAR_NAME') — active method for CI/CD
      +-- reads from the OS shell environment of the Ansible process
      +-- NOT from $GITHUB_ENV directly — that file is GitHub's
          internal mechanism, only GH Actions steps read it

    the chain:
      GH workflow fetches secret from Secrets Manager
        +-- writes to $GITHUB_ENV (GitHub mechanism)
        +-- next step resolves ${{ env.VAULT_UNSEAL_ACCESS_KEY }}
        |   into the real value
        +-- builds SSH command:
        |     export VAULT_UNSEAL_ACCESS_KEY='AKIAXXXXX' && ansible-playbook ...
        +-- Ansible runs in that shell
        +-- lookup('env', 'VAULT_UNSEAL_ACCESS_KEY') reads from shell
        +-- value lands in vault_aws_access_key_id
        +-- template vault.env.j2 renders it into /etc/vault.d/vault.env
            on each vault node

    the export step exists because Ansible doesn't know about GitHub.
    when you SSH to the ansible node, you're in a raw shell. the export
    is what puts the value into that shell so Ansible can find it.

    Ansible Vault encrypted vars — the old method, now commented out in
    group_vars. used during manual testing before CI/CD was wired up.
    both methods reference the same variable name — the source changes.


### The Credential Wipe Incident

got burned once: env vars were not set (env lookup returned empty),
the template ran and wrote an empty file to /etc/vault.d/vault.env
on the vault nodes — wiping the existing credentials.

    fix — when condition guards the template task:
      when:
        - vault_aws_access_key_id is defined
        - vault_aws_access_key_id | length > 0
        - vault_aws_secret_access_key is defined
        - vault_aws_secret_access_key | length > 0

    both variables must exist AND not be empty for the task to run.
    if either is missing → task skipped → existing file untouched.
    protects against accidental wipe if the secret was removed from
    AWS or the env var injection failed upstream.

    no_log: true on that task — Ansible shows the task name but
    replaces all output with "censored". without it, the access key
    and secret would appear plaintext in Ansible stdout, which is
    visible in the GH Actions log.


### FreeIPA CA — How Vault Nodes Get TLS Certificates

a certificate proves identity, signed by a CA that others trust.
it contains: the server's name, the server's public key, and the
CA's signature covering both.

    every domain-joined node gets /etc/ipa/ca.crt when it joins
      +-- this is FreeIPA's CA public cert
      +-- means every node trusts any cert FreeIPA CA has signed

    for the vault cluster: each node runs ipa-getcert request
    to get its own cert from FreeIPA CA.

    what happens when vault2 connects to vault1:
      vault1 presents tls.crt to vault2
        +-- vault2 checks signature against /etc/ipa/ca.crt → valid
        +-- vault2 sends encrypted challenge using vault1's public key
        +-- vault1 decrypts using tls.key (private key, only vault1 has)
        +-- vault2: confirmed, connection established

    this is a TLS handshake. FreeIPA is NOT contacted during this —
    the CA signature is baked into the cert, vault2 verifies locally.

    the cert is public, the private key is the secret. copying
    someone's cert is useless without their private key — you can't
    answer the decryption challenge. tls.key is chmod 600, readable
    only by the vault user.


### Service Principals and the -K Flag

a service principal = identity for a specific service on a host.
format: service/hostname. so vault/vault1.lab.local = "the Vault
service running on vault1."

    why they must be created before requesting certs:
      FreeIPA CA won't sign a cert for an unregistered service.
      ipa-getcert request -K vault/vault1.lab.local is an
      authorization gate — FreeIPA checks "does this service exist,
      and is this the host registered for it?"

    what -K prevents:
      with -K (current setup):
        vault2 runs ipa-getcert request -K vault/vault1.lab.local
          +-- FreeIPA: is vault2 the registered host? NO → REJECTED

      without -K (imaginary):
        vault2 runs ipa-getcert request -N CN=vault1.lab.local
          +-- FreeIPA: cert claiming vault1? sure, here you go
          +-- vault2 now has a valid FreeIPA-signed cert for vault1
          +-- any domain node trusts it → impersonation possible

    -K is a security control, not a functional requirement. the cert
    would work for TLS either way — the difference is whether any
    domain member can impersonate any other.

    certmonger runs on vault nodes and auto-renews certs before expiry.
    after renewal it runs systemctl reload vault so the new cert is
    picked up without manual intervention.


### What Is KMS

AWS Key Management Service. holds an encryption key that never
leaves AWS hardware. you send data TO KMS, it returns ciphertext.
you send ciphertext TO KMS, it returns plaintext. the actual key
only exists inside AWS's hardware security modules — never
downloadable.

    the key: alias/vault-unseal
      +-- points to key ID 8ee1fa60-10cf-48c9-afe4-4f97cc218091
      +-- can reference it by alias, key ID, or full ARN
      +-- using alias in vault.hcl.j2 because it's readable and
          survives key rotation (update alias to point to new key,
          config doesn't change)


### KMS Key Policy — 3 Levels of Access

the vault-unseal IAM user has NO IAM policy attached. can do
nothing in the account. the permission to use KMS lives inside
the KMS key policy itself, not in IAM.

Resource: "*" in a KMS key policy means THIS KEY ONLY — it's
self-referential. the policy lives inside the key, so * = myself.

    root account → kms:*
      +-- full access, AWS requires this as fallback
      +-- without it, you can lock yourself out of the key
          permanently with no way back
      +-- not used operationally

    admin users (GUI admin + TF admin role) → manage only
      +-- kms:Create, Describe, Enable, Update, Delete
      +-- can manage the key's lifecycle
      +-- explicitly CANNOT encrypt or decrypt
      +-- they administer, they don't use

    vault-unseal user → use only
      +-- kms:Encrypt, Decrypt, DescribeKey
      +-- can USE the key for encryption/decryption
      +-- CANNOT modify or delete it

    clean separation: admins manage, vault uses.
    neither can do the other's job.


### The 5 Keys vs KMS — Two Separate Things

common confusion — these are completely different and unrelated:

    5 unseal/recovery keys
      +-- generated by vault operator init
      +-- Vault uses Shamir's Secret Sharing to split the master
      |   key into 5 shares
      +-- in manual unseal: 3 of 5 humans each provide their share
      |   to reconstruct the master key
      +-- in auto-unseal (current): these become RECOVERY keys
      +-- stored in AWS Secrets Manager as emergency-only backup
      +-- not used for normal startup

    KMS auto-unseal
      +-- the operational path
      +-- Vault wraps (encrypts) its master key using KMS
      +-- stores the encrypted blob in its Raft data directory
      +-- on every startup: Vault reads blob → sends to KMS
      |   → gets decrypted → uses master key to unseal
      +-- no humans needed

    both exist simultaneously — KMS is primary, recovery keys
    are the emergency fallback if KMS becomes unavailable.


### Where Is the Master Key

never explicitly configured — generated automatically during
vault operator init:

    vault operator init ran
      +-- Vault generated a master key (random, never shown)
      +-- Vault saw seal "awskms" { kms_key_id = "alias/vault-unseal" }
      |   in vault.hcl
      +-- Vault sent master key to KMS → KMS encrypted → returned ciphertext
      +-- Vault stored ciphertext inside /opt/vault/data (Raft storage)
      +-- Vault generated 5 recovery keys from master key
          → saved to Secrets Manager

    the encrypted master key lives embedded inside Vault's Raft
    storage. not a visible file. every restart: Vault reads that
    encrypted blob → sends to KMS → gets decrypted → unsealed.


### Vault Human Auth — FreeIPA LDAP

LDAP (Lightweight Directory Access Protocol) is how external
services query FreeIPA's user and group directory. FreeIPA runs
389 Directory Server under the hood.

    user enters vault_operator + password in Vault UI/CLI
      |
      +-- Vault LDAP auth backend sends BIND request to FreeIPA
      |     (port 636, LDAPS)
      |
      +-- FreeIPA validates the password → YES / NO
      |
      +-- Vault queries FreeIPA: what groups is this user in?
      |     FreeIPA returns: vault-admins
      |
      +-- Vault checks its LOCAL mapping:
      |     vault write auth/ldap/groups/vault-admins policies=super_admin
      |
      +-- Vault issues token with super_admin policy attached

    IPA's role: authentication only — password check + group membership.
    IPA knows nothing about Vault policies. it answers two questions:
      1. is this password correct?
      2. what groups is this user in?

    vault-admins group in FreeIPA has no special attributes, no rules,
    no policies attached. it's just a group name. Vault is the one that
    gives that name meaning by mapping it to super_admin.

    the mapping (vault write auth/ldap/groups/...) is stored in Vault.
    it's Vault config, not IPA config.

    FreeIPA = phone book.
    Vault = the building that calls the phone book to verify identity,
    then applies its own rules for what you can do inside.


### Certificate Coverage — Who Signs What

    connection                                who signs        why trust works
    ──────────────────────────────────────────────────────────────────────────
    vault nodes ↔ each other (Raft)           FreeIPA CA       all vault nodes have /etc/ipa/ca.crt
    k8s vault-injector → Vault API            FreeIPA CA       k8s nodes are domain-joined
    k8s nodes ↔ each other (API, kubelet)     k8s internal CA  separate PKI from kubeadm, unrelated to FreeIPA

    k8s internal certs are completely separate. kubeadm generates
    its own CA at /etc/kubernetes/pki/ca.crt during cluster init.
    k8s components (API server, kubelet, etcd) use that PKI.
    nothing to do with FreeIPA.


### The Full Chain — End to End

    TF creates: vault-unseal IAM user (no IAM policy)
      +-- TF creates: access key + secret key for that user
      +-- TF creates: KMS key with policy allowing vault-unseal
      |   to encrypt/decrypt
      +-- TF stores: access key + secret into Secrets Manager
      |   (same module, same state file — avoids cross-state imports)
      |
      +-- GH workflow fetches from Secrets Manager
      +-- exports into SSH shell as env vars
      +-- Ansible lookup('env') reads them
      +-- template renders into /etc/vault.d/vault.env
      |   (protected by when condition against empty values)
      +-- Vault reads vault.env at startup → gets AWS credentials
      +-- Vault calls KMS Decrypt with encrypted master key blob
      +-- KMS checks key policy: is vault-unseal user allowed? YES
      +-- KMS returns decrypted master key
      +-- Vault unseals → Raft storage accessible
      +-- Vault loads LDAP auth config → ready for human login
      +-- certmonger keeps TLS certs auto-renewed in background


### Known Gaps

1. long-lived IAM access keys for vault-unseal user
     static access keys, not OIDC. don't expire. if rotated or
     deleted, every vault node loses auto-unseal on restart.
     rotation requires: generate new keys → update Secrets Manager
     → re-run vault workflow → verify unseal. no automation for this.
     accepted — keys scoped to KMS only, stored with restricted access.

2. recovery keys stored as a single secret
     all 5 recovery keys stored together in Secrets Manager.
     anyone who reads that secret has all 5 — full recovery capability.
     the threshold (3 of 5) only helps against partial compromise.
     accepted — access requires the infra role, already the most
     privileged operational entity.

3. vault.env contains plaintext AWS credentials on disk
     /etc/vault.d/vault.env on each vault node holds KMS access key
     and secret in plaintext. protected by chmod 600 owned by vault user.
     if node is compromised, credentials extractable. blast radius
     limited: attacker can unseal Vault data they have the encrypted
     blob for. not arbitrary AWS access.

4. credential wipe risk without guard
     the when condition was added after an incident. any new template
     task that handles secrets should follow the same pattern — check
     both defined and length > 0 before writing. not enforced by
     any linter or test.

5. certmonger single point of renewal
     if certmonger stops or the FreeIPA CA is unreachable at renewal
     time, vault TLS certs expire and inter-node Raft communication
     breaks. certmonger retries, but extended FreeIPA outage =
     vault cluster TLS failure. monitored by checking cert expiry dates.
