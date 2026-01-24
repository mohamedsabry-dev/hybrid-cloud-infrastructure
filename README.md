# Hybrid Cloud Infrastructure

Infrastructure as Code (IaC) repository for hybrid cloud environment spanning AWS and on-premises VMware infrastructure.

## Repository Structure

```
hybrid-cloud-infrastructure/
├── terraform/              # All Terraform configurations
│   ├── aws/                # AWS resources (vpc, eks, s3-backend)
│   ├── vmware/             # VMware vSphere (vcenter, vms, esxi)
│   ├── onprem/             # On-prem services (truenas, pfsense, vault, freeipa)
│   └── modules/            # Reusable Terraform modules
├── ansible/                # All Ansible automation
│   ├── playbooks/          # Playbooks by purpose
│   ├── roles/              # Reusable Ansible roles
│   ├── inventory/          # Inventory files
│   └── group_vars/         # Group variables
├── kubernetes/             # Kubernetes manifests & Helm charts
│   ├── manifests/          # Raw YAML manifests (onprem, eks)
│   └── helm-charts/        # Helm chart definitions
├── scripts/                # All scripts by language
│   ├── bash/               # Bash scripts (setup, utilities)
│   ├── bootstrap/          # Bootstrap/initialization scripts
│   ├── python/             # Python scripts (automation, API clients)
│   └── powershell/         # PowerShell scripts (VMware, Veeam, DR)
├── docs/                   # Documentation
│   ├── architecture/       # Architecture diagrams & decisions
│   ├── runbooks/           # Operational runbooks
│   └── troubleshooting/    # Troubleshooting guides
├── legacy/                 # Previous project files (archived)
└── .github/                # GitHub Actions & configs
```

## Quick Start

### Prerequisites

- Terraform >= 1.5.0
- Ansible >= 2.14
- AWS CLI v2
- PowerCLI (for VMware)
- kubectl

### Getting Started

```bash
git clone https://github.com/YOUR_USERNAME/hybrid-cloud-infrastructure.git
cd hybrid-cloud-infrastructure
```

## Service Overview

| Service | Purpose | Status |
|---------|---------|--------|
| AWS | Cloud infrastructure (VPC, EKS, S3) | Planned |
| VMware | On-premises virtualization | Planned |
| pfSense | Network firewall/VPN | Planned |
| FreeIPA | Identity & DNS management | Planned |
| TrueNAS | Network storage (NFS/iSCSI) | Planned |
| Vault | Secrets management | Planned |
| Kubernetes | Container orchestration | Planned |
| Jenkins | CI/CD automation | Planned |
| Veeam | Backup & recovery | Planned |
| Monitoring | Prometheus/Grafana stack | Planned |

## Documentation

- [Architecture Overview](docs/architecture/)
- [Runbooks](docs/runbooks/)
- [Naming Conventions](docs/naming-conventions.md)
- [Tagging Strategy](docs/tagging-strategy.md)

