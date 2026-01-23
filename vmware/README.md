# VMware Infrastructure

All VMware vSphere/ESXi infrastructure code and documentation.

## Structure

```
vmware/
├── terraform/              # Terraform for vSphere provider
│   ├── vcenter/            # vCenter resources
│   ├── esxi-nested/        # Nested ESXi deployment
│   ├── virtual-machines/   # VM provisioning
│   ├── network/            # DVS, port groups
│   └── modules/            # Reusable vSphere modules
├── ansible/                # ESXi/vCenter configuration
│   ├── playbooks/
│   │   ├── esxi-config/
│   │   └── vcenter-config/
│   └── roles/
├── powershell/             # PowerCLI scripts
│   ├── storm3/
│   ├── vcenter-automation/
│   └── vm-management/
├── docs/                   # VMware documentation
├── manual-configs/         # GUI configs, exports
│   ├── vcenter/
│   └── esxi/
├── troubleshooting-cases/  # VMware troubleshooting
└── exports/                # Config backups
```

## Prerequisites

- VMware vSphere 7.0+
- vCenter Server
- PowerCLI installed
- Terraform vSphere provider

## Getting Started

```bash
# PowerCLI connection
Connect-VIServer -Server vcenter.local

# Terraform
cd terraform/vcenter
terraform init
```
