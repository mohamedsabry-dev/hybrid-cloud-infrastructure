# AWS Vault-Trust — design notes

Why this module looks the way it does. The concern is narrow: the
etcd-backup CronJob inside Kubernetes needs AWS credentials to upload
snapshots to S3. Three options were considered; the third one (this
module) is what landed.

---

## Three options for "pod needs AWS creds"

### Option 1 — Long-lived IAM keys in a k8s Secret (rejected)

Simplest: create a single IAM user, generate access keys, base64 them,
mount as env vars. Rejected for the same reason Vault exists at all —
long-lived keys in a k8s Secret defeat the purpose. Leak risk, no rotation
story, always-valid credentials even when the pod isn't running.

### Option 2 — IRSA (rejected — not available)

IAM Roles for Service Accounts is the AWS-native answer: annotate a k8s
SA with a role ARN, and AWS federates to the cluster's OIDC provider. No
static keys anywhere.

It's the right answer — but it requires EKS or a manually-built OIDC
federation between the cluster and AWS IAM. On self-managed k8s that's
doable (stand up an OIDC issuer for the cluster, register it in AWS IAM,
install a mutating admission webhook) but it's a whole project in itself.
Out of scope for this phase.

### Option 3 — Vault AWS Secrets Engine (chosen)

Vault has a built-in AWS Secrets Engine. Configure it once with a single
IAM user's credentials (the `vault_trust` user this module provisions),
and it can mint short-lived STS credentials on demand for any role that
user can assume.

Wins:
- **No long-lived keys in k8s.** The only long-lived keys are `vault_trust`'s,
  and they live in Vault's own storage (raft, encrypted at rest), not in k8s.
- **Automatic expiry.** Vault credentials have a 1-hour TTL. Even if a
  credential leaks, it's dead within the hour.
- **Scoped per app.** Vault's `etcd-backup` auth role is bound to the
  `etcd-backup-sa` ServiceAccount in `kube-system` only. Another pod in
  another namespace can't get these credentials.
- **Audit trail.** Every credential issuance is logged in Vault's audit log.
- **Works on self-managed k8s** — uses the existing Vault Agent Injector
  pattern every other app already uses.

## The assume-role chain

Two identities, one assumes the other:

  vault_trust (IAM user, long-lived keys stored in Vault's config)
    │
    │  sts:AssumeRole
    ▼
  etcd-backup (IAM role)
    trust policy: vault_trust only
    permission policy: s3:PutObject on the etcd backup bucket

The trust policy on `etcd-backup` whitelists `vault_trust` as the only
identity that can assume it. Even if `vault_trust`'s keys leaked, they
could only assume this one role — not get raw S3 access, not get broader
AWS access.

This is the core of the "narrow blast radius" idea: long-lived credentials
(vault_trust's keys) are stored in one place (Vault raft) and can only be
used to mint short-lived credentials for ONE specific role. The
permission-bearing identity (etcd-backup) has no long-lived credentials of
its own.

## Why the etcd-backup role has four S3 actions, not just PutObject

The CronJob today only uploads snapshots (`PutObject`), but I gave the
role a slightly broader set upfront:

- `ListBucket` — validate that the backup landed (the CronJob checks
  existence after upload)
- `GetObject` — needed if I later add a download step to the etcd job
  (pull a snapshot for local restore), or if I need to grab a snapshot
  manually via CLI during a recovery
- `DeleteObject` — cleanup of old snapshots if I add retention logic
  inside the job instead of relying solely on S3 lifecycle rules

I'd rather set these once now than circle back to reconfigure IAM
mid-incident when I actually need to download a backup. The blast radius
is still narrow — all four actions are scoped to this one bucket only,
and the role is only assumable by `vault_trust`.

## Why the bucket lives in this module and not in network/

The S3 bucket is logically part of this concern — Vault mints credentials
to write to THIS bucket. Keeping bucket + IAM role + trust chain in one
module means the whole pattern is visible in one place, and tearing it
down (or rebuilding for a disaster) happens as one atomic change instead
of across two modules.

Tradeoff: the bucket isn't in network/ where other AWS-network resources
live. That's fine — buckets aren't really "network" resources and this
one's access pattern is tied specifically to Vault/etcd-backup. Keeping
it here is the cleaner split.

## 1-hour TTL — why this specific number

Tradeoff between two risks:

- **Shorter TTL** (5 min): credentials expire faster, leaked-credential
  risk is lower. But if a CronJob run takes longer than the TTL (large
  snapshot + slow upload), creds expire mid-upload and the run fails.
- **Longer TTL** (6 hours): creds could persist across multiple CronJob
  runs or past pod death. Leaked credential exploit window gets longer.

1 hour is long enough for every etcd-backup run to finish with margin
(snapshots ~100 MB, uploads take seconds) AND short enough that a leaked
credential is operationally dead within a single operational shift.
