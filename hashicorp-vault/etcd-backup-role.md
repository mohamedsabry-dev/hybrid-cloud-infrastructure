# Vault AWS Secrets Engine for etcd backup — the assume-role chain

The least-documented piece of the Vault story anywhere else in the repo, and the piece I was least sure about when I built it. This file is the only place where the full chain gets written up: why etcd backup needs AWS credentials, why I refused to stash long-lived AWS keys in a Kubernetes Secret, how Vault's AWS Secrets Engine mints temporary STS credentials on demand, and the exact `vault_trust` user → `etcd-backup` role → S3 bucket permission chain that makes it work. The high-level placement is in [`DESIGN.md`](DESIGN.md) "sixth shift"; this file is the detail.

---

## The problem

The etcd backup CronJob needs to upload etcd snapshots to S3 on a schedule (e.g., every 6 hours). That means:

1. The CronJob's pod needs to run `etcdctl snapshot save` against the cluster's etcd (or equivalent — I'm using the k8s-native approach via a CronJob that shells into etcd).
2. The resulting snapshot file needs to go to S3, in the etcd-backup bucket for this env.
3. Uploading to S3 requires **AWS credentials** with `s3:PutObject` permission on that bucket.

Requirement 3 is where it gets interesting. Because there are three shapes this could take, and two of them are wrong.

## Three ways I could have done this, two of which are wrong

### Option 1 — Long-lived IAM user + access key baked into a K8s Secret (WRONG)

The "naive" approach: provision an IAM user `etcd-backup-uploader` in AWS, generate an access key, base64-encode it, put it in a Kubernetes Secret, mount the Secret as env vars in the CronJob. The pod reads `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` from env, `aws s3 cp` uploads the file, done.

Why this is wrong:

1. **Long-lived AWS keys in a k8s Secret.** The whole point of running Vault in the first place is to not do this. If a k8s Secret leaks (accidental `kubectl get secret -o yaml` into a chat, etcd snapshot itself gets exfiltrated, a compromised pod in the same namespace reads it, RBAC misconfiguration exposes it) → an attacker has long-lived AWS credentials with S3 write access, and nothing in AWS knows to revoke them unless I notice the leak and rotate.
2. **No rotation story.** IAM user keys don't rotate themselves. I'd have to write another automation to rotate them on a schedule, re-generate the K8s Secret, restart the CronJob. That's a whole new thing to build.
3. **Principle of least privilege is weakened.** The credentials are always valid — they don't expire based on use. A compromised pod with those keys can run uploads at 3am for a month before I notice.

Contradicts the reason Vault exists. Rejected.

### Option 2 — IRSA (IAM Roles for Service Accounts) (BLOCKED — EKS-only)

The AWS-native pattern for this exact problem. In EKS, you can annotate a k8s ServiceAccount with `eks.amazonaws.com/role-arn: arn:aws:iam::...:role/etcd-backup`, and EKS's pod identity webhook injects the necessary env vars + projected token so the pod gets temporary STS credentials via the IAM role. No long-lived keys, automatic rotation, IAM-native.

This is the *right* answer. But I'm not on EKS — I'm on self-managed k8s on Proxmox. IRSA requires the cluster to be integrated with AWS IAM's identity federation, which EKS does for you as part of the control plane. Reproducing IRSA on self-managed k8s is possible but non-trivial (set up an OIDC provider for the cluster, register it in AWS IAM, configure the pod identity webhook or mutating admission for SA-annotation handling). It's a project in itself.

Possible in principle, out of scope for now. Rejected on "too much to build."

### Option 3 — Vault AWS Secrets Engine (WHAT I DID)

Vault has a built-in AWS Secrets Engine. You configure it once with a single IAM user's credentials (a **root-ish** user called `vault_trust` that can assume other roles), and then Vault can mint short-lived STS credentials on demand for any role that user can assume. Apps talk to Vault via the Vault Agent sidecar (same pattern as every other app in the cluster), ask for "AWS credentials for the etcd-backup role," get back `access_key_id` + `secret_access_key` + `session_token` valid for ~1 hour, use them to upload to S3, discard them when the pod exits.

Wins:

- **No long-lived AWS keys in k8s.** The only long-lived keys are `vault_trust`'s, and they live in Vault's own storage (raft, encrypted at rest), not in k8s.
- **Automatic expiry.** Every credential issued by Vault AWS Secrets Engine has a TTL. Even if a credential leaks, it's dead within the hour.
- **Scoped per app.** The `etcd-backup` Vault role is bound to the `etcd-backup-sa` ServiceAccount in `kube-system` only. Another pod in another namespace can't ask for these credentials, even if it somehow reaches Vault.
- **Audit trail.** Every credential issuance is logged in Vault's audit log. I can see "pod in kube-system asked for etcd-backup creds at 14:00 UTC" forever.
- **Works on self-managed k8s.** This is the critical one — it doesn't require IRSA, doesn't require EKS, just requires Vault + the existing Vault Agent Injector pattern every other app already uses.

Chosen. This is what's running today.

## How the chain works, end to end

```
AWS side:
  IAM user: vault_trust                    ← Vault authenticates here
     │ has sts:AssumeRole permission on
     ▼
  IAM role: etcd-backup                    ← the actual permission-bearing identity
     │ trust policy: allow vault_trust to assume
     │ permission policy: s3:PutObject on etcd-backup-<env>-bucket
     ▼
  S3 bucket: etcd-backup-<env>-<region>    ← the upload target

Vault side:
  Secrets Engine: aws
    config:
      access_key=<vault_trust's access key>
      secret_key=<vault_trust's secret key>
      region=us-east-1 (dev) / eu-west-2 (prod)
    role: etcd-backup
      credential_type: assumed_role
      role_arns: [arn:aws:iam::<account>:role/etcd-backup]
      default_ttl: 1h
      max_ttl: 1h
  Auth method: kubernetes (already configured for the cluster)
    role: etcd-backup
      bound_service_account_names: etcd-backup-sa
      bound_service_account_namespaces: kube-system
      policies: etcd-backup-aws-policy
  Policy: etcd-backup-aws-policy
    path "aws/creds/etcd-backup" { capabilities = ["read"] }

Kubernetes side:
  Namespace: kube-system
  ServiceAccount: etcd-backup-sa
  Secret: etcd-backup-sa-token (long-lived SA token)
  CronJob: etcd-backup
    template:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "etcd-backup"
        vault.hashicorp.com/tls-secret: "vault-ca"
        vault.hashicorp.com/agent-inject-secret-aws-creds: "aws/creds/etcd-backup"
        vault.hashicorp.com/agent-inject-template-aws-creds: |
          {{- with secret "aws/creds/etcd-backup" -}}
          export AWS_ACCESS_KEY_ID={{ .Data.access_key }}
          export AWS_SECRET_ACCESS_KEY={{ .Data.secret_key }}
          export AWS_SESSION_TOKEN={{ .Data.security_token }}
          {{- end }}
      spec:
        serviceAccountName: etcd-backup-sa
        containers:
          - name: etcd-backup
            # entrypoint sources /vault/secrets/aws-creds, then runs:
            #   etcdctl snapshot save /tmp/snap.db
            #   aws s3 cp /tmp/snap.db s3://etcd-backup-<env>-<region>/snap-$(date).db
```

The flow per CronJob run:

1. Kubernetes scheduler triggers the CronJob → creates a Job → creates a Pod.
2. Injector webhook sees the annotations on the Pod, injects `vault-agent-init` + `vault-agent` containers.
3. Init container authenticates to Vault using the mounted SA token + the `etcd-backup` Kubernetes auth role.
4. Vault's Kubernetes auth method validates the JWT via the cluster-side `vault-auth` SA (token review API), returns a Vault token with the `etcd-backup-aws-policy` policy.
5. Init container reads `aws/creds/etcd-backup` from Vault.
6. Vault's AWS Secrets Engine sees the read, uses `vault_trust`'s credentials to call AWS STS `AssumeRole` against the `etcd-backup` role, gets back temp credentials with a 1-hour TTL, returns them to the init container.
7. Init container renders the template to `/vault/secrets/aws-creds` (a file with shell `export` lines).
8. Init exits. Main container starts.
9. Main container's entrypoint sources `/vault/secrets/aws-creds` to load the env vars, then runs `etcdctl snapshot save` + `aws s3 cp`.
10. Upload completes, pod exits, temp credentials expire within the hour regardless.

## What got provisioned — per layer

### AWS side (Terraform)

Module: [`../terraform/dev/aws/vault-trust/`](../terraform/dev/aws/vault-trust/) (dev) / [`../terraform/prod/aws/vault-trust/`](../terraform/prod/aws/vault-trust/) (prod).

| Resource | Purpose | File |
|----------|---------|------|
| `aws_iam_user "vault_trust"` | The IAM user Vault authenticates as to call STS on behalf of itself. | [`iam.tf`](../terraform/dev/aws/vault-trust/iam.tf) |
| `aws_iam_access_key` for `vault_trust` | Long-lived keys for Vault to use — stored in AWS Secrets Manager at `<env>/vault/aws-secrets-engine-credentials`, injected into Vault's config via the Ansible trust playbook. | [`iam.tf`](../terraform/dev/aws/vault-trust/iam.tf) |
| IAM policy on `vault_trust` | Grants `sts:AssumeRole` against the `etcd-backup` role ARN. Nothing else. | [`iam.tf`](../terraform/dev/aws/vault-trust/iam.tf) |
| `aws_iam_role "etcd-backup"` | The permission-bearing role. Trust policy: only `vault_trust` can assume. Permission policy: `s3:PutObject` on the etcd backup bucket. | [`iam.tf`](../terraform/dev/aws/vault-trust/iam.tf) |
| `aws_s3_bucket "etcd-backup"` | The destination bucket. Versioning enabled, lifecycle policy for retention. | [`s3.tf`](../terraform/dev/aws/vault-trust/s3.tf) |
| `aws_secretsmanager_secret "vault_trust_credentials"` | Stores `vault_trust`'s access key + secret key for Ansible to fetch. | [`secrets.tf`](../terraform/dev/aws/vault-trust/secrets.tf) |

### Vault side (Ansible)

Playbook: [`../ansible/dev/playbooks/vault/vault-trust-aws.yml`](../ansible/dev/playbooks/vault/vault-trust-aws.yml) (and prod equivalent).

What the playbook does:

1. Enables the AWS Secrets Engine at the default path (`aws/`).
2. Reads `vault_trust`'s credentials from AWS Secrets Manager at `<env>/vault/aws-secrets-engine-credentials`.
3. Configures the engine with `vault write aws/config/root` passing the access key + secret key + region.
4. Creates the Vault role `etcd-backup` with `vault write aws/roles/etcd-backup` specifying `credential_type=assumed_role` and the etcd-backup role ARN from Terraform outputs.
5. Writes the Vault policy `etcd-backup-aws-policy` granting read on `aws/creds/etcd-backup`.
6. Writes the Kubernetes auth role `etcd-backup` binding the policy to `etcd-backup-sa` in `kube-system`.

Idempotent — re-running doesn't break anything, just no-ops where state already matches.

### Kubernetes side (Flux-managed manifest)

CronJob: [`../kubernetes/dev/deployments/apps/etcd-backup/cronjob.yaml`](../kubernetes/dev/deployments/apps/etcd-backup/cronjob.yaml) (and prod equivalent).

SA + token Secret in the same manifest (or a companion file — check `kustomization.yaml`). IPA CA Secret at [`../kubernetes/dev/deployments/apps/etcd-backup/vault-ca-secret.yaml`](../kubernetes/dev/deployments/apps/etcd-backup/vault-ca-secret.yaml).

One note: because the CronJob runs in `kube-system`, it required the injector-into-system-namespace RBAC change (`[TS-K8S-017]`). Without that, the Vault Agent Injector webhook skips pods in `kube-system` and the annotations are ignored — the pod starts without the init container and the upload fails. Resolved by adjusting the injector's ClusterRole to permit system-namespace pods.

## The two AWS secrets you'll see side by side

To avoid confusion — there are two separate AWS secrets in Secrets Manager, belonging to this and the neighboring concerns:

| Secret | Purpose | Consumer |
|--------|---------|----------|
| `<env>/vault/unseal-credentials` | Access keys for the **`vault_unseal`** IAM user, used for KMS Decrypt during Vault auto-unseal | Vault itself, via `vault.env` systemd EnvironmentFile |
| `<env>/vault/aws-secrets-engine-credentials` | Access keys for the **`vault_trust`** IAM user, used by Vault's AWS Secrets Engine to call STS AssumeRole | Vault's AWS Secrets Engine configuration, set once by the `vault-trust-aws.yml` Ansible playbook |

Two separate IAM users, two separate AWS secrets, two separate Vault setup paths. `vault_unseal` and `vault_trust` do different things and should never be confused.

## Why the ttl is 1 hour specifically

The `default_ttl=1h` on the Vault role is a tradeoff between:

- **Shorter TTL** (e.g., 5 minutes) → credentials expire faster, leaked credentials are lower-risk. But if the CronJob run takes longer than the TTL (e.g., because the snapshot is large and the S3 upload is slow over a limited link), the creds expire mid-upload and the `aws s3 cp` fails partway through. Re-requesting creds from Vault mid-pod is possible but requires the sidecar (not just the init container) and careful coordination.
- **Longer TTL** (e.g., 6 hours) → the creds could plausibly be used across multiple CronJob runs, or persist past the pod's lifetime. Leaked creds have a longer effective exploit window.

1 hour is long enough that I'm confident every CronJob run finishes with margin (snapshots are ~100MB, uploads take seconds on my link). It's short enough that a leaked credential is dead within an operationally meaningful window. If snapshots grow significantly I'd reconsider, but at current scale 1h is right.

## Failure modes

| Scenario | Symptom | Fix |
|----------|---------|-----|
| `vault_trust`'s access keys revoked in AWS | Vault's AWS engine config is broken; `vault read aws/creds/etcd-backup` returns auth error | Regenerate IAM user keys in AWS, update Secrets Manager, re-run `vault-trust-aws.yml` |
| `etcd-backup` IAM role deleted | Vault can call STS but AssumeRole fails with `role does not exist` | Re-run Terraform apply to recreate the role |
| S3 bucket policy changed | Upload fails with `AccessDenied` | Check bucket policy / role permission policy |
| Vault sealed | Pod can't auth to Vault, stuck in Init | Fix Vault seal state (see [`kms-unseal.md`](kms-unseal.md)) |
| FreeIPA DNS down | Vault Agent can't resolve vault.lab.local | See `[TS-K8S-033]` — wait for IPA, no clean fix yet |
| Vault Kubernetes auth role misconfigured | Pod auth fails with "service account not authorized" | Check `bound_service_account_names` and `bound_service_account_namespaces` match the pod's actual SA |

## Why I didn't write this up before

Honestly, because I built it late in the project and then moved on to the next thing. Every other piece of the Vault story has a dedicated doc somewhere — the Kubernetes integration has `vault-k8s-integration-guide.txt`, the KMS unseal has the terraform module's README plus Ansible decision logs, the troubleshooting has TS cases. But the AWS Secrets Engine for etcd backup was a single Ansible playbook + a single CronJob manifest + a single Terraform module, and I never wrote up *why* those three things were the shape of the solution. This file is that write-up. It's the piece of the Vault story that would have been the hardest to reconstruct from the code alone.

## Related files

- **Terraform:** [`../terraform/dev/aws/vault-trust/`](../terraform/dev/aws/vault-trust/) / [`../terraform/prod/aws/vault-trust/`](../terraform/prod/aws/vault-trust/)
- **Ansible setup playbook:** [`../ansible/dev/playbooks/vault/vault-trust-aws.yml`](../ansible/dev/playbooks/vault/vault-trust-aws.yml) / [`../ansible/prod/playbooks/vault/vault-trust-aws.yml`](../ansible/prod/playbooks/vault/vault-trust-aws.yml)
- **Kubernetes CronJob:** [`../kubernetes/dev/deployments/apps/etcd-backup/cronjob.yaml`](../kubernetes/dev/deployments/apps/etcd-backup/cronjob.yaml) / [`../kubernetes/prod/deployments/apps/etcd-backup/cronjob.yaml`](../kubernetes/prod/deployments/apps/etcd-backup/cronjob.yaml)
- **GitHub workflow:** [`../.github/workflows/dev-aws-vault-trust.yml`](../.github/workflows/dev-aws-vault-trust.yml) / [`../.github/workflows/prod-aws-vault-trust.yml`](../.github/workflows/prod-aws-vault-trust.yml)
- **Integration guide (if it mentions this):** [`../deployment-docs/k8s-etcd-vault-aws-integration.txt`](../deployment-docs/k8s-etcd-vault-aws-integration.txt)
- **DR test:** [`../disaster-recovery/etcd-backup-s3.md`](../disaster-recovery/etcd-backup-s3.md) — tests the upload path end-to-end
- **Related TS cases:** `[TS-K8S-017]` system-namespace injection (required for this CronJob in kube-system)
- **Related Vault files:** [`k8s-integration.md`](k8s-integration.md) (the injection pattern this relies on), [`kms-unseal.md`](kms-unseal.md) (Vault has to be unsealed for any of this to work)
