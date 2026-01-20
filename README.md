# Hybrid Cloud Infrastructure

Infrastructure as Code (IaC) repository for hybrid cloud environment spanning AWS and on-premises VMware infrastructure.

## Repository Structure

```
hybrid-cloud-infrastructure/
├── aws/                    # AWS cloud infrastructure
├── vmware/                 # VMware vSphere/ESXi infrastructure
├── pfsense/                # pfSense firewall/router
├── freeipa/                # FreeIPA identity management
├── truenas/                # TrueNAS storage
├── vault/                  # HashiCorp Vault secrets management
├── kubernetes/             # Kubernetes clusters (on-prem & EKS)
├── cicd/                   # CI/CD pipelines (Jenkins & GitHub Actions)
├── veeam/                  # Veeam backup infrastructure
├── monitoring/             # Prometheus & Grafana monitoring
├── shared/                 # Shared modules, roles, and scripts
├── docs/                   # Project-wide documentation
├── legacy/                 # Previous project files (archived)
└── .github/                # GitHub-specific configurations
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
- [Phase Implementations](docs/phase-implementations/)
- [Standards & Conventions](shared/docs/standards/)

## License

MIT License - see [LICENSE](LICENSE)
