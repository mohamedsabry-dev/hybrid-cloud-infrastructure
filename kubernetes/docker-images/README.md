# Docker Images

Custom container images for K8s workloads that need tools not available in
standard base images. Both are published to GHCR and referenced by the
deployments in `../dev/deployments/apps/` and `../prod/deployments/apps/`.

---

## Images

### remediation

Python 3.11 image for the worker node self-healing Deployment. The actual
remediation script isn't baked in — it's mounted via ConfigMap at runtime,
so logic changes don't require a rebuild.

**Base:** `python:3.11-slim`

**Included tools:**
- `kubectl` (latest stable)
- `python` libraries: `kubernetes`, `requests`, `proxmoxer`
- Network debugging: `ping`, `traceroute`, `dig`/`nslookup`, `netcat`, `curl`
- General: `jq`, `vim`, `ps`, `ssh`

**Build & push:**
```bash
docker build -t ghcr.io/mohamedsabry-dev/remediation:latest .
docker push ghcr.io/mohamedsabry-dev/remediation:latest
```

**Used by:** `kubernetes/{dev,prod}/deployments/apps/remediation/deployment.yaml`
**CI workflow:** `.github/workflows/build-docker-remediation.yml`

---

### etcd-backup

Alpine image for the daily etcd snapshot CronJob. Bundles `etcdctl` for
snapshots, AWS CLI for S3 uploads, and `kubectl` for cluster interaction.

**Base:** `alpine:3.19`

**Included tools:**
- `etcdctl` v3.5.12
- `aws` CLI
- `kubectl` (latest stable)
- Network debugging: `ping`, `dig`/`nslookup`, `netcat`, `curl`
- General: `jq`, `vim`, `openssl`, `bash`, `tar`, `gzip`

**Build & push:**
```bash
docker build -t ghcr.io/mohamedsabry-dev/etcd-backup:latest .
docker push ghcr.io/mohamedsabry-dev/etcd-backup:latest
```

**Used by:** `kubernetes/{dev,prod}/deployments/apps/etcd-backup/cronjob.yaml`
**CI workflow:** `.github/workflows/build-docker-etcd-backup.yml`
