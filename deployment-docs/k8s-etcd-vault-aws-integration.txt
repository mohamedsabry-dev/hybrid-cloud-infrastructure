# etcd Backup with Vault AWS Integration
# ========================================
# Complete Guide - Tested & Working

## Architecture Overview

```
K8s CronJob Pod (runs on master node)
      │
      ├──► 1. Get temp AWS creds from Vault (via Vault Agent Init)
      │
      ├──► 2. Backup etcd locally (hostPath on master)
      │
      └──► 3. Upload to S3

Result: 2 backup sources (local + S3), pod dies, keys expire
```

## Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│  K8s Cluster (Master Node)                                          │
│                                                                     │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  etcd Backup CronJob                                        │    │
│  │  - ServiceAccount: etcd-backup-sa                           │    │
│  │  - Vault annotations (agent-inject, pre-populate-only)      │    │
│  │  - hostPath: /var/lib/etcd-backup (local on master)        │    │
│  │  - hostNetwork: true (to reach etcd on 127.0.0.1)          │    │
│  └───────────────────────┬────────────────────────────────────┘    │
│                          │                                          │
└──────────────────────────┼──────────────────────────────────────────┘
                           │ K8s Auth (ServiceAccount JWT)
                           ▼
                     ┌──────────┐
                     │  Vault   │
                     │          │
                     │  AWS     │
                     │  Secrets │
                     │  Engine  │
                     └────┬─────┘
                          │ STS AssumeRole (temp credentials)
                          ▼
                     ┌──────────┐
                     │   AWS    │
                     │   S3     │
                     └──────────┘
```

## Deployment Order - Step by Step

```
STEP 1: Terraform (AWS) [MANUAL via GitHub Actions]
────────────────────────────────────────────────────
Trigger: Push to dev-security branch OR workflow_dispatch
Path: terraform/dev/aws/vault-trust/
Workflow: .github/workflows/dev-aws-vault-trust.yml


STEP 2: Ansible (Vault) [MANUAL]
────────────────────────────────
Path: ansible/dev/playbooks/vault/vault-trust-aws.yml
Vars: ansible/dev/inventory/group_vars/vault_cluster.yml
Run:
  cd ansible/dev
  ansible-playbook playbooks/vault/vault-trust-aws.yml --ask-vault-pass


STEP 3: Docker Image [AUTO on push to dev]
──────────────────────────────────────────
Path: kubernetes/docker-images/etcd-backup/Dockerfile
Workflow: .github/workflows/build-docker-images.yml
Trigger: Push changes to kubernetes/docker-images/etcd-backup/**
IMPORTANT: Make image PUBLIC in GitHub Packages!


STEP 4: K8s Manifests [AUTO via Flux]
─────────────────────────────────────
Path: kubernetes/dev/deployments/apps/etcd-backup/
Files:
  - kustomization.yaml
  - namespace.yaml
  - service-account.yaml
  - vault-ca-secret.yaml
  - configmap.yaml
  - cronjob.yaml
Trigger: Push changes to kubernetes/dev/deployments/apps/etcd-backup/**


STEP 5: Test [MANUAL]
─────────────────────
Run:
  kubectl create job --from=cronjob/etcd-backup etcd-backup-test -n etcd-backup
  kubectl get pod -n etcd-backup -w
  kubectl logs -n etcd-backup -l app=etcd-backup -f
```
etcd-20260410-170134.snap
snap
April 10, 2026, 19:01:36 (UTC+02:00)
34.9 MB
Standard

# =============================================================================
# LAYER 1: TERRAFORM (AWS Resources)
# =============================================================================

## Files Location
```
terraform/dev/aws/vault-trust/
├── provider.tf    # AWS provider, S3 backend
├── main.tf        # Documentation
├── iam.tf         # User, roles, policies
├── secrets.tf     # Secrets Manager
└── s3.tf          # S3 bucket
```

## Resources Created

### 1. IAM User (for Vault → AWS authentication)
```hcl
resource "aws_iam_user" "vault_trust" {
  name = "vault_trust"
  path = "/system/"
}

resource "aws_iam_access_key" "vault_trust" {
  user = aws_iam_user.vault_trust.name
}
```

### 2. Secrets Manager (store IAM keys)
```hcl
resource "aws_secretsmanager_secret" "vault_aws_creds" {
  name = "vault/aws-secrets-engine-credentials"
}

resource "aws_secretsmanager_secret_version" "vault_aws_creds" {
  secret_id = aws_secretsmanager_secret.vault_aws_creds.id
  secret_string = jsonencode({
    access_key = aws_iam_access_key.vault_trust.id
    secret_key = aws_iam_access_key.vault_trust.secret
  })
}
```

### 3. User Policy (allow AssumeRole)
```hcl
resource "aws_iam_user_policy" "vault_assume_roles" {
  name = "vault-assume-backup-roles"
  user = aws_iam_user.vault_trust.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = [aws_iam_role.etcd_backup.arn]
    }]
  })
}
```

### 4. IAM Role (Vault assumes this)
```hcl
resource "aws_iam_role" "etcd_backup" {
  name = "etcd-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { AWS = aws_iam_user.vault_trust.arn }
    }]
  })
}
```

### 5. Role Policy (S3 permissions)
```hcl
resource "aws_iam_role_policy" "etcd_backup_s3" {
  name = "etcd-backup-s3-access"
  role = aws_iam_role.etcd_backup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ]
      Resource = [
        "arn:aws:s3:::${aws_s3_bucket.etcd_backup.id}",
        "arn:aws:s3:::${aws_s3_bucket.etcd_backup.id}/*"
      ]
    }]
  })
}
```

### 6. S3 Bucket
```hcl
resource "aws_s3_bucket" "etcd_backup" {
  bucket = "hybrid-cloud-k8s-etcd-backup-dev"
}
```

## Trust Relationship (Two-Way Handshake)
```
User Policy:                        Role Trust Policy:
"I can assume role X"      <──>     "User Y can assume me"
```

## Deploy Terraform
```bash
cd terraform/dev/aws/vault-trust
terraform init
terraform plan
terraform apply
```

# =============================================================================
# LAYER 2: VAULT CONFIGURATION (via Ansible)
# =============================================================================

## Playbook Location
```
ansible/dev/playbooks/vault/vault-trust-aws.yml
```

## Prerequisites - Encrypted Variables
```
ansible/dev/inventory/group_vars/vault_cluster.yml

# Contains (inline encrypted with ansible-vault encrypt_string):
aws_account_id: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  ...
access_key: !vault |
  ...
secret_key: !vault |
  ...
region: !vault |
  ...
```

## What Ansible Does

### 1. Enable AWS Secrets Engine (idempotent)
```bash
vault secrets enable aws
```

### 2. Configure Root Credentials
```bash
vault write aws/config/root \
  access_key="..." \
  secret_key="..." \
  region="us-east-1"
```

### 3. Create Vault AWS Role
```bash
vault write aws/roles/etcd-backup \
  credential_type=assumed_role \
  role_arns="arn:aws:iam::<ACCOUNT_ID>:role/etcd-backup-role" \
  default_sts_ttl=1h \
  max_sts_ttl=2h
```

### 4. Create Vault Policy (IMPORTANT: correct path!)
```bash
vault policy write etcd-backup-policy - <<EOF
path "aws/creds/etcd-backup" {
  capabilities = ["read"]
}
EOF
```

### 5. Bind K8s ServiceAccount to Vault Role
```bash
vault write auth/kubernetes/role/etcd-backup \
  bound_service_account_names=etcd-backup-sa \
  bound_service_account_namespaces=etcd-backup \
  policies=etcd-backup-policy \
  ttl=1h
```

## Run Ansible Playbook
```bash
cd ansible/dev
ansible-playbook playbooks/vault/vault-trust-aws.yml --ask-vault-pass
```

## Test Vault Configuration
```bash
# On Vault server
vault read aws/creds/etcd-backup

# Expected output:
# Key                Value
# ---                -----
# access_key         ASIA...
# secret_key         xyz...
# security_token     FwoG...
# ttl                1h
```

# =============================================================================
# LAYER 3: DOCKER IMAGE
# =============================================================================

## Dockerfile Location
```
kubernetes/docker-images/etcd-backup/Dockerfile
```

## Image Contents
- etcdctl (v3.5.12)
- aws cli
- kubectl
- Common utilities (curl, jq, vim, bash, etc.)

## Build Workflow
```
.github/workflows/build-docker-images.yml

Triggers on:
- Push to dev branch with changes in kubernetes/docker-images/**
- Manual workflow_dispatch

Builds:
- ghcr.io/mohamedsabry-dev/etcd-backup:latest
- ghcr.io/mohamedsabry-dev/remediation:latest
```

## IMPORTANT: Image Visibility
Make sure image is PUBLIC in GitHub Packages settings, otherwise K8s can't pull without imagePullSecrets.

# =============================================================================
# LAYER 4: KUBERNETES MANIFESTS
# =============================================================================

## Files Location
```
kubernetes/dev/deployments/apps/etcd-backup/
├── kustomization.yaml
├── namespace.yaml
├── service-account.yaml
├── vault-ca-secret.yaml
├── configmap.yaml       # Backup script
└── cronjob.yaml
```

## Key Configuration Points

### 1. Runs on Master Nodes Only
```yaml
nodeSelector:
  node-role.kubernetes.io/control-plane: ""
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
```

### 2. Host Network (to reach etcd on 127.0.0.1)
```yaml
hostNetwork: true
dnsPolicy: ClusterFirstWithHostNet
```

### 3. Vault Agent Injection (pre-populate only, no sidecar)
```yaml
annotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/agent-pre-populate-only: "true"
  vault.hashicorp.com/role: "etcd-backup"
  vault.hashicorp.com/agent-inject-secret-aws: "aws/creds/etcd-backup"
  vault.hashicorp.com/agent-inject-template-aws: |
    {{- with secret "aws/creds/etcd-backup" -}}
    export AWS_ACCESS_KEY_ID="{{ .Data.access_key }}"
    export AWS_SECRET_ACCESS_KEY="{{ .Data.secret_key }}"
    export AWS_SESSION_TOKEN="{{ .Data.security_token }}"
    export AWS_DEFAULT_REGION="us-east-1"
    {{- end }}
```

### 4. Local Storage (hostPath, not NFS)
```yaml
volumes:
  - name: backup-storage
    hostPath:
      path: /var/lib/etcd-backup
      type: DirectoryOrCreate
  - name: etcd-certs
    hostPath:
      path: /etc/kubernetes/pki/etcd
      type: Directory
```

### 5. Script as ConfigMap
```yaml
volumes:
  - name: script
    configMap:
      name: etcd-backup-script
      defaultMode: 0755

command: ["bash", "/scripts/backup.sh"]
```

## Backup Script Flow
```bash
1. Take etcd snapshot → /backup/etcd-YYYYMMDD-HHMMSS.snap
2. Verify snapshot
3. Load AWS creds → source /vault/secrets/aws
4. Upload to S3 → aws s3 cp
5. Cleanup old local backups (>7 days)
```

# =============================================================================
# TESTING
# =============================================================================

## Manual Test Run
```bash
# Create test job from cronjob
kubectl create job --from=cronjob/etcd-backup etcd-backup-test -n etcd-backup

# Watch pod status
kubectl get pod -n etcd-backup -w

# Expected progression:
# Init:0/1 → PodInitializing → Running → Completed

# View logs
kubectl logs -n etcd-backup -l app=etcd-backup -f
```

## Troubleshooting

### Init Container Stuck
```bash
# Check vault-agent-init logs
kubectl logs <pod> -n etcd-backup -c vault-agent-init

# Common issues:
# - 403 Permission Denied → Vault policy wrong path or not attached
# - Auth error → K8s role not bound to ServiceAccount
```

### Image Pull Error
```bash
# Check if image is public
docker pull ghcr.io/mohamedsabry-dev/etcd-backup:latest

# If 401 Unauthorized → make image public in GitHub
```

### Policy Wrong Path
```bash
# Check policy on Vault
vault policy read etcd-backup-policy

# MUST be:
# path "aws/creds/etcd-backup" { capabilities = ["read"] }

# NOT:
# path "secret/data/..." ← WRONG!
```

# =============================================================================
# BACKUP LOCATIONS
# =============================================================================

```
Every 6 hours (schedule: "0 */6 * * *"):

Local (master node):
  /var/lib/etcd-backup/etcd-20260410-120000.snap

S3 (disaster recovery):
  s3://hybrid-cloud-k8s-etcd-backup-dev/etcd-20260410-120000.snap
```

# =============================================================================
# SECURITY SUMMARY
# =============================================================================

| Component              | Location                      | Security               |
|------------------------|-------------------------------|------------------------|
| Vault IAM User keys    | AWS Secrets Manager           | Initial setup only     |
| AWS temp credentials   | /vault/secrets/aws (in pod)   | Short-lived (1hr), auto-expire |
| etcd backup data       | hostPath + S3                 | Encrypted at rest      |
| K8s ServiceAccount     | etcd-backup namespace         | RBAC controlled        |
| Vault policy           | etcd-backup-policy            | Least privilege        |

# =============================================================================
# PROD DEPLOYMENT
# =============================================================================

Mirror all files to prod:
- terraform/prod/aws/vault-trust/
- kubernetes/prod/deployments/apps/etcd-backup/
- .github/workflows/prod-aws-vault-trust.yml

Change:
- S3 bucket name: hybrid-cloud-k8s-etcd-backup-prod
- Region: eu-west-2 (or your prod region)
- AWS account variables
