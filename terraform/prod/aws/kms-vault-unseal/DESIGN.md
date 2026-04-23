# AWS KMS Vault Unseal module — design notes

Why Vault uses AWS KMS for auto-unseal and how the key policy is
structured.

---

## Why KMS auto-unseal instead of manual Shamir keys

Vault starts sealed. Without auto-unseal, every Vault restart (node
reboot, container restart, crash) requires manually providing 3 of 5
Shamir key shares before Vault serves traffic. In a home lab with 3 Vault
nodes, that means any power outage requires me to manually unseal each
node before the cluster is usable.

KMS auto-unseal replaces the Shamir process: Vault encrypts its master key
with the KMS key at init time, and on startup it calls KMS Decrypt to
recover it automatically. No human intervention, no key shares to
distribute, no 3am unsealing after a power blip.

The tradeoff: Vault now depends on AWS KMS availability. If KMS is
unreachable (AWS outage, network partition, credential expiry), Vault
can't unseal. For a home lab that already depends on AWS for the VPN
tunnel, this adds no new blast radius — if AWS is down, the tunnel is
down too and the cluster is already degraded.

## Why a dedicated IAM user instead of a role

The `vault-unseal` IAM user exists solely to hold credentials that the
on-prem Vault nodes use to call KMS. A role would be cleaner (no
long-lived keys), but Vault's KMS seal stanza needs static credentials —
there's no instance profile or OIDC federation available on self-managed
on-prem nodes. The user is scoped to only `kms:Encrypt`, `kms:Decrypt`,
and `kms:DescribeKey` on this specific key.

## KMS key policy — three principal tiers

The key policy has three statements, each for a different principal:

1. **Root account** — full `kms:*`. Required by AWS as a fallback so the
   key is never unrecoverable. If all other principals are deleted or
   their policies break, root can still manage the key.

2. **Key administrators** (admin user + TerraformAdmin role) — management
   actions only (Create, Describe, Enable, List, Put, Update, Revoke,
   Disable, Get, Delete, ScheduleKeyDeletion, CancelKeyDeletion). They
   can rotate, disable, or delete the key, but they cannot use it for
   encrypt/decrypt. This separation means even if TerraformAdmin is
   compromised, the attacker can't decrypt Vault's master key.

3. **Vault unseal user** — usage actions only (Encrypt, Decrypt,
   DescribeKey). Can use the key but can't manage it — can't disable it,
   can't schedule deletion, can't change the policy.

This admin/user split follows the KMS best practice of separating key
management from key usage.

## Why enable_key_rotation = true

AWS rotates the backing key material annually. Old ciphertext still
decrypts (AWS keeps old key versions), but new encrypt operations use the
new material. This is free and automatic — no reason not to enable it.

## Why recovery keys are stored in Secrets Manager

When Vault initializes with KMS auto-unseal, it produces recovery keys
instead of unseal keys. Recovery keys can't unseal Vault (KMS does that),
but they're needed for specific operations: generating a root token,
rekeying, or migrating away from KMS unseal.

Storing them in Secrets Manager (`{env}/vault/unseal-keys`) keeps them
off-disk and access-controlled. The secret is created by Terraform with
placeholders; the actual recovery keys are populated once during
`vault operator init` — same create/populate split as the secrets module.
