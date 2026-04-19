# AWS KMS auto-unseal — the deep dive

Why I unseal Vault with AWS KMS instead of manual Shamir, how the credential-injection chain works from AWS Secrets Manager all the way down to the systemd environment file on the Vault nodes, why the "empty KMS credentials" incident (`[TS-VLT-003]`) happened and what I changed to make it impossible again, and the explicit dependency-on-AWS tradeoff this brings with it. The high-level story is in [`DESIGN.md`](DESIGN.md) — this file is the operational and security detail behind the "fifth shift" section there.

---

## The problem being solved

Vault starts sealed. "Sealed" means Vault holds the encrypted form of its master key in memory but cannot decrypt it — all API endpoints return `503 sealed`. The default unseal mechanism is **Shamir key sharing**: you split the master key into N shares with threshold T (default 5/3), distribute them to separate humans, and after any restart each human provides their share via `vault operator unseal <share>` until the threshold is met. That's the "production" story; in practice the shares end up stored in 1Password or equivalent because nobody runs a real key-ceremony for a lab.

For me, the friction is that restarts happen often in this lab:

- After a patch run by Ansible
- After a config change to `vault.hcl`
- After a VIP drill (I want to test failover)
- After any Proxmox-side operation (snapshot, move, reboot) that touches the LXC container
- After an accidental kernel panic on a host (rare, but non-zero)

Every restart = three SSH sessions and three `vault operator unseal` commands on each of three nodes. Nine unseal commands to bring the cluster back. That's operationally unsustainable in a lab with two operators (me, and me tired at 11pm).

**Auto-unseal via AWS KMS** replaces that loop. Vault, on startup, asks AWS KMS to decrypt its stored encrypted-master-key blob. If KMS returns the decrypted value, Vault unseals automatically. If KMS refuses (credentials bad, network unreachable, key deleted), Vault stays sealed and I fall back to manual unseal using the master recovery keys. No human in the loop for the normal-case restart.

## What got provisioned in AWS

Terraform owns the AWS side. Module: [`../terraform/dev/aws/kms-vault-unseal/`](../terraform/dev/aws/kms-vault-unseal/) (dev) / [`../terraform/prod/aws/kms-vault-unseal/`](../terraform/prod/aws/kms-vault-unseal/) (prod). Each env has its own key in its own AWS account.

| Resource | Purpose | File |
|----------|---------|------|
| `aws_kms_key "vault_unseal"` | The symmetric KMS key whose `Encrypt`/`Decrypt` operations Vault uses to wrap its master key. Auto-rotation enabled. | [`kms.tf`](../terraform/dev/aws/kms-vault-unseal/kms.tf) |
| `aws_kms_alias "alias/vault-unseal"` | Stable alias so Vault's `seal "awskms"` config references an alias, not a key ID that could rotate. | [`kms.tf`](../terraform/dev/aws/kms-vault-unseal/kms.tf) |
| `aws_iam_user "vault_unseal"` | Dedicated IAM user for Vault. Not reused for anything else. | [`user.tf`](../terraform/dev/aws/kms-vault-unseal/user.tf) |
| IAM policy on the KMS key | Grants `vault_unseal` only `Encrypt`/`Decrypt`/`DescribeKey` on this specific key. No `CreateKey`, no cross-key access, no admin operations. Root account has admin fallback. `TerraformAdmin` role has key-admin permissions for Terraform to manage it. | [`kms.tf`](../terraform/dev/aws/kms-vault-unseal/kms.tf) |
| `aws_iam_access_key` for `vault_unseal` | Long-lived access key + secret key for the user. | [`user.tf`](../terraform/dev/aws/kms-vault-unseal/user.tf) |
| `aws_secretsmanager_secret "unseal_credentials"` | Stores the access key + secret key in AWS Secrets Manager at `<env>/vault/unseal-credentials`. This is the *credential distribution* point — Ansible reads from here at runtime. | [`secret.tf`](../terraform/dev/aws/kms-vault-unseal/secret.tf) |
| `aws_secretsmanager_secret "unseal_keys"` | Stores the **master recovery keys** from `vault operator init` at `<env>/vault/unseal-keys`. Separate from the credentials; these are the "break glass" keys. | [`secret.tf`](../terraform/dev/aws/kms-vault-unseal/secret.tf) |

The outputs from this module are ARNs (key, user, secrets) that can be referenced by other modules if needed, but in practice the only downstream consumer is the Ansible vault_setup playbook, which reads from AWS Secrets Manager by secret name.

## Two sets of secrets, two different purposes

This is important and worth being explicit about. There are **two** secrets that live in AWS Secrets Manager under `<env>/vault/`, and they do different things:

| Secret | Contents | When used |
|--------|----------|-----------|
| `<env>/vault/unseal-credentials` | IAM access key + secret key for user `vault_unseal` | Every time Vault starts normally — Vault reads these from its env file, authenticates to KMS, decrypts its master key, unseals. |
| `<env>/vault/unseal-keys` | Master recovery keys from `vault operator init` | **Only in break-glass scenarios.** If KMS is unreachable, or the KMS key is deleted/disabled, or the IAM user's keys are revoked, I need these to manually unseal Vault using `vault operator unseal <recovery-key>`. |

Losing the `unseal-credentials` is fixable — regenerate the IAM user's access keys in AWS, update the Secrets Manager entry, re-run the Ansible playbook to push the new keys to the Vault nodes. No data loss.

Losing the `unseal-keys` is **catastrophic**. Without either KMS access or the recovery keys, Vault's encrypted master-key blob is just ciphertext I can't decrypt. I can reinstall Vault, but I've lost every secret it held. That's why the recovery keys live in AWS Secrets Manager (where they're protected by AWS IAM, backed up by AWS's durability guarantees, accessible from any machine with an IAM session) and not on my laptop's filesystem or a local 1Password vault.

## The credential-injection chain

This is the part that went wrong once (`[TS-VLT-003]`) and is now protected by a guard. The chain that gets the `vault_unseal` IAM keys onto the Vault nodes so they can be read by the Vault process:

```
AWS Secrets Manager
  (<env>/vault/unseal-credentials)
       │
       │ (1) GitHub Actions workflow [prod|dev]-vault-full-setup.yml
       │     reads the secret via aws-actions/configure-aws-credentials@v4
       │     + aws secretsmanager get-secret-value
       │
       ▼
  Workflow environment variables
  (VAULT_UNSEAL_ACCESS_KEY, VAULT_UNSEAL_SECRET_KEY)
       │
       │ (2) Workflow passes them to ansible-playbook via -e flags or vars
       │
       ▼
  Ansible runtime variables
  (inside vault_setup.yml task scope)
       │
       │ (3) Ansible template task renders vault.env.j2 on each Vault node,
       │     substituting the variables into the systemd EnvironmentFile
       │     format expected by Vault's unit file
       │
       ▼
  /etc/vault.d/vault.env (on each node)
  AWS_ACCESS_KEY_ID=AKIA...
  AWS_SECRET_ACCESS_KEY=...
  AWS_REGION=us-east-1     # dev (eu-west-2 for prod)
       │
       │ (4) systemd unit `vault.service` loads this as EnvironmentFile=
       │     before ExecStart; Vault process sees them as env vars
       │
       ▼
  Vault server process
  Reads AWS_ACCESS_KEY_ID from env, authenticates to KMS endpoint,
  calls kms:Decrypt on its stored encrypted master key,
  unseals itself, becomes active.
```

Every step in that chain has to succeed. Every hop is a place where the secret can be lost or corrupted. The failure mode that actually happened is step (1) or (2) being skipped — which brings us to the incident.

## The `[TS-VLT-003]` incident: empty KMS credentials

The full troubleshooting write-up is [`../troubleshooting/vault/3-vault-kms-credentials-overwrite-empty-vars.md`](../troubleshooting/vault/3-vault-kms-credentials-overwrite-empty-vars.md). Short version of what happened:

I ran the Ansible `vault_setup.yml` playbook **manually** from my Mac Mini, bypassing GitHub Actions. The manual run didn't have the GH Actions secret-fetch step in front of it, so the `VAULT_UNSEAL_ACCESS_KEY` and `VAULT_UNSEAL_SECRET_KEY` variables were **empty strings** — not unset (which would have caused Ansible to fail with "undefined variable"), but present-and-empty.

The template task happily rendered the `vault.env` with empty values:

```
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_REGION=us-east-1
```

Vault started, tried to authenticate to KMS with empty credentials, got `InvalidSignature` / `AccessDenied` back, and **stayed sealed**. Symptom at the time was "Vault won't unseal after restart" with a generic-looking KMS error in journalctl.

Time to root cause: about an hour of tailing logs, re-checking the KMS key's IAM policy, re-checking the IAM user's access key status in AWS, before I realized the `vault.env` on the node had empty strings in it. The playbook had "succeeded" — it had rendered a file — but the file was useless.

### The fix

A `when:` gate was added to the templating task in [`../ansible/dev/playbooks/vault/vault_setup.yml`](../ansible/dev/playbooks/vault/vault_setup.yml) that asserts the credentials have non-zero length before rendering. Something like:

```yaml
- name: Render vault.env with AWS KMS credentials
  ansible.builtin.template:
    src: vault.env.j2
    dest: /etc/vault.d/vault.env
    owner: vault
    group: vault
    mode: "0400"
  when:
    - vault_unseal_access_key | default('') | length > 0
    - vault_unseal_secret_key | default('') | length > 0
```

If either credential is empty, the task is **skipped** — which means `vault.env` is not overwritten (preserving any valid version already in place), and the playbook logs a visible "skipped due to missing credentials" message. The empty-string render is no longer silently possible.

### The deeper lesson

The lesson isn't "add a `when:` gate" — that's the fix. The lesson is: **silent empty-string substitution is a whole class of bugs**. Any time I template a file from variables, the failure mode of "variable defined but empty" needs to be treated as distinct from "variable undefined." The former is more dangerous because it doesn't fail loudly. This lesson shaped how I write Ansible tasks in general now; the `vault.env` template is just where I learned it.

### Why this specifically happened

Because I ran the playbook manually. That bypass exists because the GitHub Actions workflow requires a network round-trip through GitHub (pushing a branch, triggering the workflow, waiting for it to run) and sometimes I just want to re-apply a small change locally without that ceremony. The bypass itself is fine — what wasn't fine was that the playbook didn't defend against being run without the credential-fetch layer in front of it. Now it does. Manual runs that don't have credentials in their env will skip the vault.env templating and leave the existing file intact.

## How it runs in GitHub Actions

The automated path is in [`../.github/workflows/prod-vault-full-setup.yml`](../.github/workflows/prod-vault-full-setup.yml) (and dev equivalent). The relevant steps:

1. **AWS credentials:** `aws-actions/configure-aws-credentials@v4` assumes the `TerraformAdmin` role via OIDC (not static keys — those are the bootstrap-only user's problem, not this workflow's).
2. **Fetch unseal credentials:** A step runs `aws secretsmanager get-secret-value --secret-id prod/vault/unseal-credentials` and parses the JSON into two workflow outputs (`access_key`, `secret_key`).
3. **Pass to Ansible:** The `ansible-playbook` invocation includes `-e "vault_unseal_access_key=${{ steps.get_secret.outputs.access_key }}"` and similar for the secret.
4. **Playbook runs vault_setup.yml:** Which templates `vault.env.j2` on each node with the now-populated variables. The `when:` gate passes because both are non-empty.
5. **Vault restarts:** After the env file is in place, the playbook triggers a `vault.service` restart. Vault comes up, reads `vault.env`, authenticates to KMS, unseals, becomes active.

The 3-minute review window in the workflow (pause between Terraform plan and apply) is my standard pattern for any workflow that touches infrastructure — gives me a window to catch a misconfiguration in the plan output before it applies.

## The AWS dependency, made explicit

Running KMS auto-unseal means: **Vault cannot start without reaching AWS KMS.** That's a dependency I deliberately accepted. The full list of scenarios this creates:

| Scenario | Vault behavior | Recovery |
|----------|---------------|----------|
| Normal restart, KMS reachable, IAM keys valid | Auto-unseals in seconds. | None needed. |
| AWS region outage | Vault stays sealed on restart; existing unsealed Vault keeps working (the master key is in memory, KMS isn't in the data path). | Wait for AWS region; or, if urgent, manual-unseal using recovery keys from AWS SM (via AWS console from any other region's console access) — see the DR test at [`../disaster-recovery/vault-aws-kms-dependency.md`](../disaster-recovery/vault-aws-kms-dependency.md). |
| Network partition (lab can't reach internet → AWS) | Same as region outage — Vault stays sealed after restart, existing session stays up. | Fix the network partition; or manual-unseal if needed urgently. |
| `vault_unseal` IAM user's keys revoked / rotated | Auto-unseal fails. | Regenerate IAM user's keys in AWS, update `<env>/vault/unseal-credentials` in Secrets Manager, re-run Ansible playbook to re-template vault.env, restart Vault. |
| KMS key deleted by accident | Catastrophic — the encrypted master-key blob cannot be decrypted anymore. | Manual unseal with recovery keys from `<env>/vault/unseal-keys`. This is the *only* way back. |
| Recovery keys lost | Irrecoverable. All Vault secrets lost. | Reinstall Vault, lose all existing secrets, re-enroll all apps. |

The last row is why recovery keys live in AWS Secrets Manager with versioning enabled and an explicit resource policy allowing only the root account and `TerraformAdmin` to read them. It's the last line of defense and it's protected accordingly.

## Why AWS KMS specifically — alternative options considered

- **Shamir (default)** — manual unseal every restart. Rejected on operational grounds.
- **Transit auto-unseal (another Vault cluster)** — would turn Vault-unseal into a Vault-cluster dependency, which is circular. Also adds another Vault to maintain.
- **HSM** — no HSM in the lab. Would need hardware purchase, far out of scope.
- **GCP KMS / Azure Key Vault** — would require setting up a separate cloud dependency. I'm already in AWS, so AWS KMS was the path of least resistance.
- **cloudhsm-auto-unseal** — AWS CloudHSM is expensive (~$1/hour per HSM) and overkill for a lab.

AWS KMS is free to use beyond the minimal request volume of an unseal every few days, takes 5 minutes to set up via Terraform, and fits the pattern I already have (AWS account, IAM users, Secrets Manager, Terraform). It's not the most secure option on paper (KMS is a software-based KMS, not an HSM), but it's the right-sized answer for this phase of the lab.

## Related files

- [`../terraform/dev/aws/kms-vault-unseal/`](../terraform/dev/aws/kms-vault-unseal/) — dev KMS module
- [`../terraform/prod/aws/kms-vault-unseal/`](../terraform/prod/aws/kms-vault-unseal/) — prod KMS module
- [`../ansible/dev/playbooks/vault/vault_setup.yml`](../ansible/dev/playbooks/vault/vault_setup.yml) — playbook that does the credential injection
- [`../ansible/dev/playbooks/vault/templates/vault.env.j2`](../ansible/dev/playbooks/vault/templates/vault.env.j2) — the systemd EnvironmentFile template
- [`../ansible/dev/playbooks/vault/templates/vault.hcl.j2`](../ansible/dev/playbooks/vault/templates/vault.hcl.j2) — where the `seal "awskms"` stanza is configured
- [`../ansible/dev/inventory/group_vars/vault_cluster.yml`](../ansible/dev/inventory/group_vars/vault_cluster.yml) — the group_vars that documents the two credential-injection approaches (env-var lookup via workflow, Ansible Vault fallback for manual testing)
- [`../.github/workflows/dev-aws-kms-vault-unseal.yml`](../.github/workflows/dev-aws-kms-vault-unseal.yml) — Terraform apply workflow (dev)
- [`../.github/workflows/prod-aws-kms-vault-unseal.yml`](../.github/workflows/prod-aws-kms-vault-unseal.yml) — Terraform apply workflow (prod)
- [`../.github/workflows/dev-vault-full-setup.yml`](../.github/workflows/dev-vault-full-setup.yml) — end-to-end LXC + Ansible workflow (dev)
- [`../.github/workflows/prod-vault-full-setup.yml`](../.github/workflows/prod-vault-full-setup.yml) — end-to-end LXC + Ansible workflow (prod)
- [`../troubleshooting/vault/3-vault-kms-credentials-overwrite-empty-vars.md`](../troubleshooting/vault/3-vault-kms-credentials-overwrite-empty-vars.md) — the TS case behind the `when:` gate
- [`../disaster-recovery/vault-aws-kms-dependency.md`](../disaster-recovery/vault-aws-kms-dependency.md) — the DR test for KMS unavailability
- [`../deployment-docs/aws-secrets-setup-guide.txt`](../deployment-docs/aws-secrets-setup-guide.txt) — the broader AWS Secrets Manager setup (prerequisite for this whole chain)
