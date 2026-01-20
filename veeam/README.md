# Veeam Backup Infrastructure

Veeam backup and recovery configuration.

## Structure

```
veeam/
├── terraform/              # Veeam server deployment
├── ansible/                # Veeam configuration
├── manual-configs/
│   ├── backup-jobs/        # Job configurations
│   └── repository-configs/ # Repository settings
├── docs/
├── troubleshooting-cases/
└── scripts/
    └── backup-monitoring.ps1
```

## Backup Strategy

| Target | Schedule | Retention |
|--------|----------|-----------|
| VMs | Daily | 30 days |
| Databases | Hourly | 7 days |
| Config backups | Weekly | 90 days |

## Components

- Veeam Backup Server
- Backup Repository (TrueNAS)
- Backup Proxies

## Getting Started

```bash
# Deploy Veeam server
cd terraform
terraform init && terraform apply
```

## Monitoring

```powershell
# Check backup job status
./scripts/backup-monitoring.ps1
```
