# Hybrid Cloud Infrastructure

Infrastructure as Code (IaC) repository for hybrid cloud environment spanning AWS and on-premises VMware infrastructure.

## Repository Structure

```
hybrid-cloud-infrastructure/
│
├── infrastructure-core/
│   ├── compute/
│   │   ├── vmware-esxi/          # ESXi host configurations
│   │   ├── vmware-vcenter/       # vCenter server setup
│   │   └── virtual-machines/     # VM provisioning
│   ├── networking/
│   │   ├── pfsense/              # Firewall configurations
│   │   ├── vlans/                # VLAN definitions
│   │   ├── vpn/                  # VPN tunnels (site-to-site, AWS)
│   │   └── routing/              # Static/dynamic routing
│   ├── storage/
│   │   ├── truenas/              # TrueNAS configuration
│   │   ├── datastores/           # VMware datastores
│   │   └── nfs-iscsi/            # NFS/iSCSI shares
│   └── identity/
│       ├── freeipa/              # FreeIPA server setup
│       ├── users-groups/         # User/group management
│       └── dns/                  # DNS zones and records
│
├── platform-layer/
│   ├── secrets/
│   │   ├── vault-cluster/        # HashiCorp Vault HA cluster
│   │   ├── policies/             # Vault policies
│   │   └── integrations/         # Vault integrations (K8s, AWS, etc.)
│   ├── backup/
│   │   ├── veeam/                # Veeam server deployment
│   │   ├── backup-jobs/          # Backup job configurations
│   │   └── repositories/         # Backup repositories
│   ├── monitoring/
│   │   ├── prometheus/           # Prometheus server & rules
│   │   ├── grafana/              # Grafana dashboards
│   │   └── alerting/             # Alert rules and notifications
│   ├── orchestration/
│   │   ├── k8s-onprem/           # On-premises Kubernetes cluster
│   │   ├── k8s-aws/              # AWS EKS configuration
│   │   └── container-registry/   # Private container registry
│   └── cicd/
│       ├── github-actions/       # GitHub Actions workflows
│       ├── jenkins/              # Jenkins pipelines
│       └── runners/              # Self-hosted runners
│
└── application-layer/
    ├── app-ecommerce/
    │   ├── database/             # Database deployments
    │   ├── backend/              # Backend services
    │   └── frontend/             # Frontend applications
    ├── app-analytics/
    │   ├── database/             # Analytics data store
    │   ├── processing/           # Data processing pipelines
    │   └── api/                  # Analytics API
    └── app-internal-portal/
        ├── database/             # Portal database
        ├── backend/              # Portal backend
        └── frontend/             # Portal frontend
```

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
git clone https://github.com/YOUR_USERNAME/hybrid-cloud-infrastructure.git
cd hybrid-cloud-infrastructure
```

## Service Overview

| Service | Purpose | Location | Status |
|---------|---------|----------|--------|
| VMware ESXi/vCenter | On-premises virtualization | `infrastructure-core/compute/` | Planned |
| pfSense | Network firewall/VPN | `infrastructure-core/networking/pfsense/` | Planned |
| TrueNAS | Network storage (NFS/iSCSI) | `infrastructure-core/storage/truenas/` | Planned |
| FreeIPA | Identity & DNS management | `infrastructure-core/identity/freeipa/` | Planned |
| HashiCorp Vault | Secrets management | `platform-layer/secrets/vault-cluster/` | Planned |
| Veeam | Backup & recovery | `platform-layer/backup/veeam/` | Planned |
| Prometheus/Grafana | Monitoring stack | `platform-layer/monitoring/` | Planned |
| Kubernetes (On-prem) | Container orchestration | `platform-layer/orchestration/k8s-onprem/` | Planned |
| AWS EKS | Cloud Kubernetes | `platform-layer/orchestration/k8s-aws/` | Planned |
| GitHub Actions | CI/CD automation | `platform-layer/cicd/github-actions/` | Active |

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
./config.sh --url https://github.com/YOUR_ORG/hybrid-cloud-infrastructure \
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
./config.sh --url https://github.com/YOUR_ORG/hybrid-cloud-infrastructure \
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

- [Architecture Overview](docs/architecture/)
- [Runbooks](docs/runbooks/)
- [Troubleshooting Guides](docs/troubleshooting/)

## Contributing

1. Create feature branch from `main`
2. Make changes following coding standards
3. Submit pull request for review
4. Ensure CI checks pass

## License

Private repository - Internal use only.
