etcd Backup to S3 — CronJob to Snapshot to Cloud Storage (Summary Trace)
=========================================================================

pre-trace (one-time setup):
  Terraform creates IAM user (vault_trust) + IAM role (etcd-backup-role) + S3 bucket
    → Ansible configures Vault AWS secrets engine + etcd-backup role (assumed_role, 1h TTL)
    → Vault K8s auth binds etcd-backup-sa to etcd-backup policy
    → Docker image built with etcdctl + aws-cli, pushed to GHCR

daily 20:30 Cairo time → CronJob controller creates Job → Pod scheduled on master
  → hostNetwork: true (etcd on 127.0.0.1:2379), tolerates control-plane taint
    → concurrencyPolicy: Forbid, backoffLimit: 6 (~10 min retry window)

→ vault-agent-init starts → reads K8s SA JWT
  → POST /v1/auth/kubernetes/login (role: etcd-backup)
    → Vault validates via TokenReview → issues Vault token
      → GET /v1/aws/creds/etcd-backup
        → Vault calls STS AssumeRole internally
          → returns temp credentials (access_key + secret_key + session_token, 1h TTL)
            → rendered to /vault/secrets/aws as export statements
              → init exits 0 (pre-populate-only, no sidecar)

→ main container starts → bash /scripts/backup.sh
  → etcdctl snapshot save /backup/etcd-YYYYMMDD-HHMMSS.snap
    → connects https://127.0.0.1:2379 with etcd TLS certs from /etc/kubernetes/pki/etcd
      → consistent point-in-time snapshot (~37-39 MB, ~2500 keys)

→ etcdctl snapshot status → verifies hash + key count + revision
  → fail → script exits non-zero → Job failed

→ source /vault/secrets/aws → AWS env vars loaded
  → aws s3 cp → uploads snapshot to s3://hybrid-cloud-k8s-etcd-backup-{env}/
    → STS temp credentials authenticate each API call

→ find /backup -mtime +7 -delete → local cleanup (7-day retention)
  → S3: no lifecycle policy, retained indefinitely
    → script exits 0 → Job Complete → pod terminated
      → AWS creds expire after 1h, Vault token expires per TTL
