Vault Auto-Unseal — KMS Packet Flow, Security, and Encryption Layers
======================================================================

Question:
  Walk me through what happens when Vault auto-unseals with AWS KMS.
  How does the request reach AWS? How is the connection secured?
  What's in the packet? Can it be intercepted? What does "unsealed" 
  actually mean?

---

The unseal flow end-to-end:

  Vault starts → reads encrypted blob from Raft storage
    → needs to decrypt it, can't do it locally — KMS has the key

  DNS resolution:
    Vault builds endpoint from config region: kms.eu-central-1.amazonaws.com
      → Vault LXC → FreeIPA DNS (authoritative for lab.local only)
        → FreeIPA doesn't know amazonaws.com → forwards to 8.8.8.8
          → resolves KMS IP → returns to Vault
    FreeIPA MUST boot before Vault. No DNS = no KMS = no unseal.

  Network path:
    Vault LXC → VLAN → MikroTik → ISP → public internet → AWS KMS
    Does NOT go through WireGuard tunnel (that's for private VPC traffic).
    KMS is a public AWS endpoint.

  API request (single HTTPS POST):
    Vault loads access key + secret key from config file on the node.
    Vault builds the request body: encrypted blob (ciphertext).

    Authentication — AWS SigV4 (secret key NEVER sent):
      1. Vault uses secret key to SIGN the request locally (HMAC-SHA256)
      2. Signature = hash of (timestamp + region + service + request body)
      3. Header sent:
         Authorization: AWS4-HMAC-SHA256 Credential=AKIA.../date/region/kms/aws4_request, Signature=abc123...
      4. Access key ID is in the header (tells AWS which account)
      5. Secret key is NOT in the header — only the computed signature
      6. AWS looks up the secret key by access key ID → computes same
         signature → match = authenticated
      7. Signature is timestamped — expires in minutes, not replayable

  What KMS does:
    KMS receives the encrypted blob + authenticated request
      → uses its KMS key to decrypt the blob
        → returns plaintext master key in the HTTPS response

  What the packet looks like on the wire:
    TLS encrypted. Packet capture sees:
      - TLS Client Hello → Server Hello → encrypted data
      - Destination IP (KMS endpoint) and SNI hostname visible
      - Body, headers, keys, decrypted master key — all ciphertext
    Without TLS session keys, nothing useful.

---

What Vault does with the plaintext master key:

  Vault has layered encryption (key wrapping):
    Actual secrets encrypted with → encryption key
    Encryption key encrypted with → master key
    Master key encrypted with → KMS key (the blob in Raft)

  Unseal sequence:
    1. KMS decrypts blob → plaintext master key (in memory only)
    2. Master key decrypts the encryption key (in memory only)
    3. Vault is UNSEALED — barrier is open

  Unsealed does NOT mean secrets are decrypted. It means Vault now
  holds the encryption key in memory and CAN decrypt secrets on demand.

  After unseal:
    - Client requests a secret via API
    - Vault uses encryption key (already in memory) to decrypt that
      one secret from Raft → returns to client
    - Secrets decrypted on demand, not all at once

  Sealed = has locked boxes, no key to open them. API returns 503.
  Unsealed = has the key, no boxes opened yet. Waits for requests.
  Read = someone asks for a specific box, Vault opens it, hands it over.

  Plaintext master key stays in memory only. Never written to disk.
  If Vault restarts → master key gone → must ask KMS again.
  That's why it's called "auto-unseal" — repeats every restart.

---

Who can intercept and what's the risk:

  Packet capture on network: TLS ciphertext, useless.
  ISP: same, TLS ciphertext.

  MITM (Man in the Middle): someone sits between Vault and AWS,
    intercepts traffic both directions. Normally sees TLS ciphertext.
    But with a trusted CA certificate (compromised CA, corporate proxy),
    they can terminate TLS on their side, read everything in plaintext,
    create new TLS connection to AWS. Vault thinks it's talking to AWS.
    AWS thinks it's talking to Vault. Attacker sees the decrypted master
    key in the response. Very hard in practice, theoretical risk.

  Root on Vault LXC: can read config file (access+secret keys), can
    read master key from Vault's memory. Full compromise.

  AWS account access with KMS permissions: if someone has kms:Decrypt
    on your KMS key AND can get the encrypted blob from Raft storage,
    they can call KMS themselves, get the plaintext master key, and
    unseal your Vault without touching your infrastructure.
    Two pieces needed: blob + KMS access. Either alone is useless.

  Plaintext master key + Raft storage files: someone with both can
    decrypt everything offline without Vault or AWS.

---

The bootstrap problem:

  The AWS credentials in the Vault config are STATIC — access key +
  secret key in a file. You can't use Vault to manage the credentials
  that unseal Vault. Circular dependency.

  Security relies on:
    - File permissions (only vault user can read config)
    - TLS protecting the wire
    - SigV4 ensuring secret key never travels
    - KMS key policy (only this IAM user can decrypt)
    - Physical security of the LXC host
