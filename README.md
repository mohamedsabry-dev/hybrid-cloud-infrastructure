# Hybrid Cloud Infrastructure

Infrastructure as Code (IaC) repository for hybrid cloud environment spanning AWS and on-premises VMware infrastructure.

## Repository Structure

```
hybrid-cloud-infrastructure/
│
├── .github/                      # GitHub Actions workflows & CODEOWNERS
│
├── cloud/                        # Cloud infrastructure (AWS)
│   └── aws/
│       ├── bootstrap/            # Phase 0: Foundation resources
│       │   ├── cloudformation/   # OIDC, state bucket, audit bucket
│       │   └── terraform/        # CloudTrail configuration
│       ├── iam/                  # Phase 1: Identity & access
│       │   ├── cloudformation/   # Managed policies & OIDC roles
│       │   └── terraform/        # (reserved)
│       ├── network/              # VPC, subnets, gateways
│       │   └── terraform/
│       ├── compute/              # EC2, EKS, containers
│       │   └── terraform/
│       ├── storage/              # S3, EBS, EFS
│       │   └── terraform/
│       └── docs/                 # AWS-specific documentation
│
├── on-premises/                  # On-premises infrastructure (planned)
│
├── legacy/                       # Legacy configs & reference material
│   ├── DEVOPS/
│   │   ├── ansible-playbooks/    # Ansible roles (IPA, K8s, Vault, etc.)
│   │   ├── terraform/            # Legacy Terraform configs
│   │   ├── scripts/              # Bash automation scripts
│   │   └── Troubleshooting Cases/
│   └── INFRASTRUCTURE/
│       ├── Compute/              # VMware/ESXi documentation
│       ├── Network/              # Network documentation
│       ├── Storage/              # TrueNAS documentation
│       ├── Backup-DR/            # Veeam scripts & configs
│       └── DR/                   # Disaster recovery scripts
│
└── tests/                        # Infrastructure tests
    ├── phase-2/                  # Current test phase
    └── archive/                  # Archived test configs
```

## Bootstrap Infrastructure (Phase 0)

Foundation infrastructure that must be deployed first. Located in `cloud/aws/bootstrap/`.

### CloudFormation Bootstrap

Deploys core AWS resources via CloudFormation (`cloud/aws/bootstrap/cloudformation/bootstrap/`):

| Resource | Name | Purpose |
|----------|------|---------|
| OIDC Provider | GitHub Actions OIDC | Enables GitHub Actions to authenticate with AWS without long-lived credentials |
| S3 Bucket | `hybrid-cloud-infrastructure-terraform-state` | Terraform state storage (versioned, encrypted, public access blocked) |
| DynamoDB Table | `hybrid-cloud-infrastructure-terraform-state-lock` | Prevents concurrent Terraform runs |
| S3 Bucket | `hybrid-cloud-infrastructure-audit-logs` | Audit logs with 365-day retention |

**Deployment:**
```bash
aws cloudformation deploy \
  --template-file cloud/aws/bootstrap/cloudformation/bootstrap/bootstrap.yaml \
  --stack-name hybrid-bootstrap \
  --capabilities CAPABILITY_IAM
```

### Terraform Audit

Configures CloudTrail using the audit bucket created by CloudFormation (`cloud/aws/bootstrap/terraform/audit/`):

| Resource | Name | Purpose |
|----------|------|---------|
| CloudTrail | `hybrid-main-trail` | Multi-region trail with log file validation |

**Configuration:**
- Region: `eu-west-2`
- Backend: S3 state bucket with DynamoDB locking
- Logs all management events across all regions

**Deployment:**
```bash
cd cloud/aws/bootstrap/terraform/audit
terraform init
terraform apply
```

---

## IAM Infrastructure (Phase 1)

Identity and access management for GitHub Actions OIDC authentication. Located in `cloud/aws/iam/`.

### Managed Policies

Shared policies deployed via CloudFormation (`cloud/aws/iam/cloudformation/policies/`):

| Policy | Purpose |
|--------|---------|
| `HybridCloud-TerraformState-Common` | S3 + DynamoDB access for Terraform state |
| `HybridCloud-Terraform-SecurityBoundary` | Blocks IAM mutations, allows PassRole to EC2/EKS |
| `HybridCloud-NetworkFullManagement` | VPC, subnets, gateways, routes, VPN, peering |
| `HybridCloud-ApplicationFullManagement` | EC2, EKS, ECR, security groups, load balancers, NAT |
| `HybridCloud-SecurityAuditControl` | CloudTrail, CloudWatch, EventBridge, SNS |

### GitHub Actions Roles

OIDC roles for CI/CD pipelines (`cloud/aws/iam/cloudformation/roles/`):

| Role | Purpose | Attached Policies |
|------|---------|-------------------|
| `GitHubActions-Network` | Network infrastructure provisioning | TerraformState + NetworkFullManagement + ReadOnlyAccess |
| `GitHubActions-Application` | Compute and container resources | TerraformState + SecurityBoundary + ApplicationFullManagement + ReadOnlyAccess |
| `GitHubActions-Audit` | Security and monitoring setup | TerraformState + SecurityAuditControl + ReadOnlyAccess |

### Trust Policy

All roles trust GitHub OIDC with conditions:
- **Audience**: `sts.amazonaws.com`
- **Subject**: `repo:mohamedsabry-dev/hybrid-cloud-infrastructure:ref:refs/heads/main` and `mohamedsabrydev/*` branches

### Deployment

Stacks auto-deploy via **CloudFormation Git Sync**:

```
hybrid-foundation (bootstrap)
       │
       ▼
hybrid-policies ──────► Hybrid-GitSync-ServiceRoles
  (exports ARNs)           (imports via !ImportValue)
```

**Note:** If both stacks change in the same commit, roles may fail due to policy dependency. Wait for policies to complete, then re-sync roles.

---

## Security Deployment Model

Two-layer approach separating sensitive foundation resources from automated infrastructure.

```
+------------------------------------------+
|        LAYER 1: Foundation               |
|        (Manual Deploy Only)              |
|                                          |
|  - IAM Roles & Policies                  |
|  - OIDC Provider                         |
|  - Permission Boundaries                 |
|  - CloudTrail / Audit                    |
|                                          |
|  Tool: CloudFormation (Console/CLI)      |
+------------------------------------------+
                    |
                    v
+------------------------------------------+
|        LAYER 2: Infrastructure           |
|        (Automated via GitHub Actions)    |
|                                          |
|  - S3 Buckets, DynamoDB                  |
|  - VPCs, Subnets, EC2                    |
|  - Application IAM (with boundaries)     |
|                                          |
|  Tool: Terraform + GitHub Actions        |
+------------------------------------------+
```

### Layer 1: Foundation (Manual)

| Aspect | Approach |
|--------|----------|
| Deployment | Manual (AWS Console or CLI) |
| Templates | `/cloud/aws/iam/`, `/cloud/aws/bootstrap/cloudformation/` |
| Change Process | PR review → Merge → Admin deploys manually |

**Rationale:** IAM resources are too sensitive for automated deployment. Human review prevents privilege escalation.

### Layer 2: Infrastructure (Automated)

| Aspect | Approach |
|--------|----------|
| Deployment | GitHub Actions |
| Trigger | `workflow_dispatch` (manual) + `push` (feature branch testing) |
| IAM Permissions | No `iam:*` - only infrastructure actions |
| Runner | Self-hosted `production` runner |

### GitHub Actions Restrictions

The GitHub Actions IAM roles intentionally lack:
- `iam:CreateUser`, `iam:CreateRole`, `iam:*Policy*`
- `organizations:*`
- `account:*`

This prevents privilege escalation even if workflows are compromised.

### CODEOWNERS Protection

Protected paths requiring approval from `@mohamedsabrydev`:

| Path | Reason |
|------|--------|
| `/cloud/aws/iam/` | IAM templates |
| `/cloud/aws/bootstrap/cloudformation/` | Bootstrap CloudFormation |
| `/cloud/aws/bootstrap/**/backend.tf` | Terraform state config |
| `/.github/workflows/tf-bootstrap.yml` | Production deploy workflow |
| `/.github/CODEOWNERS` | This protection itself |

### Branch Protection

Required settings for `main` branch:
- Require pull request before merging
- Require at least 1 approval
- Require review from Code Owners
- Do not allow bypassing (applies to admins too)

---

## Quick Start

### Prerequisites

- Terraform >= 1.14.3
- Ansible >= 2.20.1
- AWS CLI v2.33.4
- Python >= 3.14.2
- Node.js >= 25.4.0
- Docker >= 29.1.3
- PowerShell >= 7.5.4
- kubectl

### Getting Started

```bash
git clone https://github.com/mohamedsabry-dev/hybrid-cloud-infrastructure.git
cd hybrid-cloud-infrastructure
```

## Deployment Phases

| Phase | Component | Location | Status |
|-------|-----------|----------|--------|
| 0 | Bootstrap (OIDC, State, Audit) | `cloud/aws/bootstrap/` | Active |
| 1 | IAM (Policies, Roles) | `cloud/aws/iam/` | Active |
| 2 | Network (VPC, Subnets) | `cloud/aws/network/` | In Progress |
| 2 | Compute (EC2, EKS) | `cloud/aws/compute/` | Planned |
| 2 | Storage (S3, EBS) | `cloud/aws/storage/` | Planned |
| - | On-Premises Infrastructure | `on-premises/` | Planned |

## Service Overview

| Service | Purpose | Location | Status |
|---------|---------|----------|--------|
| GitHub OIDC | Secure CI/CD authentication | `cloud/aws/bootstrap/` | Active |
| CloudTrail | API audit logging | `cloud/aws/bootstrap/terraform/audit/` | Active |
| GitHub Actions | CI/CD automation | `.github/workflows/` | Active |
| AWS VPC | Network infrastructure | `cloud/aws/network/` | In Progress |
| VMware ESXi/vCenter | On-premises virtualization | `legacy/INFRASTRUCTURE/Compute/` | Legacy |
| TrueNAS | Network storage (NFS/iSCSI) | `legacy/INFRASTRUCTURE/Storage/` | Legacy |
| FreeIPA | Identity & DNS management | `legacy/DEVOPS/ansible-playbooks/ipa/` | Legacy |
| HashiCorp Vault | Secrets management | `legacy/DEVOPS/ansible-playbooks/vault/` | Legacy |
| Veeam | Backup & recovery | `legacy/INFRASTRUCTURE/Backup-DR/` | Legacy |
| Kubernetes | Container orchestration | `legacy/DEVOPS/ansible-playbooks/k8s/` | Legacy |

---

## Local Runner Setup (macOS)

Deploy GitHub self-hosted runner on Mac for CI/CD pipelines.

### Platform Information

- **OS**: macOS (Darwin 25.2.0)
- **Architecture**: ARM64 (Apple Silicon)
- **Machine**: Mac Mini

### Dependencies

| Tool | Version | Purpose |
|------|---------|---------|
| Python | 3.14.2 | Automation scripts |
| Docker | 29.1.3 | Container builds |
| PowerShell | 7.5.4 | VMware/Windows automation |
| AWS CLI | 2.33.4 | AWS resource management |
| Terraform | 1.14.3 | Infrastructure provisioning |
| Ansible | 2.20.1 | Configuration management |
| Node.js | 25.4.0 | GitHub Actions runner |

### Installation Steps

#### 1. Install Dependencies

```bash
# Install Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required tools
brew install python@3.14 node terraform ansible awscli
brew install --cask docker powershell
```

#### 2. Download and Install GitHub Actions Runner

```bash
# Create runner directory
mkdir -p ~/actions-runner && cd ~/actions-runner

# Download latest runner (ARM64)
curl -o actions-runner-osx-arm64.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.XXX.X/actions-runner-osx-arm64-2.XXX.X.tar.gz

# Extract
tar xzf ./actions-runner-osx-arm64.tar.gz
```

#### 3. Configure Runner with Repository Token

```bash
# Get token from: GitHub Repo > Settings > Actions > Runners > New self-hosted runner

# Configure runner
./config.sh --url https://github.com/mohamedsabry-dev/hybrid-cloud-infrastructure \
  --token YOUR_RUNNER_TOKEN
```

#### 4. Setup Runner as Auto-Start Service (launchd)

```bash
# Install as service
sudo ./svc.sh install

# Start the service
sudo ./svc.sh start

# Check status
sudo ./svc.sh status
```

### Runner Configuration

#### Labels

Configure runner with the following labels:

| Label | Description |
|-------|-------------|
| `self-hosted` | Identifies as self-hosted runner |
| `macOS` | Operating system |
| `arm64` | CPU architecture |
| `mac-mini` | Machine type |
| `production` | Environment designation |

```bash
# Configure with labels during setup
./config.sh --url https://github.com/mohamedsabry-dev/hybrid-cloud-infrastructure \
  --token YOUR_TOKEN \
  --labels self-hosted,macOS,arm64,mac-mini,production \
  --name mac-mini-runner-01
```

#### Security Configuration

- **Scope**: Repository-level runner (not organization-wide)
- **Permissions**: Restrict to specific workflows
- **Workflow Triggers**: Only triggered by protected branches

#### Working Directory and Cache

```bash
# Default working directory
~/actions-runner/_work

# Configure cache directory
export ACTIONS_CACHE_DIR=~/actions-runner/_cache
```

### Validation Checklist

| Check | Command/Action | Expected Result |
|-------|----------------|-----------------|
| Runner Status | GitHub Repo > Settings > Actions > Runners | Shows "Idle" |
| Service Running | `sudo ./svc.sh status` | "Running" |
| Auto-start Test | Reboot Mac, check runner status | Runner auto-starts |
| Workflow Test | Run sample workflow | Executes successfully |

#### Sample Test Workflow

Create `.github/workflows/test-runner.yml`:

```yaml
name: Test Self-Hosted Runner

on:
  workflow_dispatch:

jobs:
  test:
    runs-on: [self-hosted, macOS, arm64]
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: System Info
        run: |
          echo "Runner: $RUNNER_NAME"
          echo "OS: $(uname -a)"
          echo "Architecture: $(uname -m)"

      - name: Verify Tools
        run: |
          python3 --version
          docker --version
          terraform --version
          ansible --version
          aws --version
          node --version
          pwsh --version
```

### Troubleshooting

#### Runner Not Starting

```bash
# Check logs
cat ~/actions-runner/_diag/Runner_*.log

# Restart service
sudo ./svc.sh stop
sudo ./svc.sh start
```

#### Runner Offline After Reboot

```bash
# Verify launchd service
sudo launchctl list | grep actions.runner

# Re-install service if needed
sudo ./svc.sh uninstall
sudo ./svc.sh install
sudo ./svc.sh start
```

---

## Documentation

| Document | Location |
|----------|----------|
| AWS Documentation | `cloud/aws/docs/` |
| IAM Troubleshooting | `cloud/aws/iam/TROUBLESHOOTING.md` |
| Legacy Troubleshooting | `legacy/*/Troubleshooting Cases/` |

## Contributing

1. Create feature branch from `main`
2. Make changes following coding standards
3. Submit pull request for review
4. Ensure CI checks pass

## License

Private repository - Internal use only.
