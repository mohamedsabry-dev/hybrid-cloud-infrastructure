# Terraform Infrastructure

Hybrid cloud infrastructure managed via GitHub Actions CI/CD.

## Structure

```
terraform/
├── dev/                    # Dev environment
│   ├── aws/
│   │   ├── bootstrap-dev.yaml   # CloudFormation bootstrap
│   │   ├── iam/                 # IAM roles & policies
│   │   └── secrets/             # Secrets Manager
│   └── proxmox/
│       ├── bootstrap-dev.sh     # Proxmox user setup
│       └── resources/           # VMs & infrastructure
│
└── prod/                   # Prod environment
    ├── aws/
    │   ├── bootstrap-prod.yaml  # CloudFormation bootstrap
    │   ├── iam/                 # IAM roles & policies
    │   └── secrets/             # Secrets Manager
    └── proxmox/
        ├── bootstrap-prod.sh    # Proxmox user setup
        └── resources/           # VMs & infrastructure
```

## Workflow

| Branch | Environment | Trigger |
|--------|-------------|---------|
| `dev`  | Dev account + Dev Proxmox | Push to dev |
| `main` | Prod account + Prod Proxmox | Push to main |

## Deployment Order

1. **Bootstrap AWS** - Deploy CloudFormation stack manually (one-time)
2. **Bootstrap Proxmox** - Run shell script on Proxmox host (one-time)
3. **IAM Module** - Creates Infrastructure role (via CI/CD)
4. **Secrets Module** - Creates Proxmox token secret (via CI/CD)
5. **Proxmox Resources** - Manages VMs & infra (via CI/CD)

## Roles

| Role | Purpose | Managed By |
|------|---------|------------|
| `GitHubActions-TerraformAdmin-{env}` | Full admin, IAM changes | CloudFormation |
| `GitHubActions-Infrastructure-{env}` | Infra only, no IAM | Terraform |

## State Management

- Each environment has its own S3 bucket + DynamoDB table
- Dev: `hybrid-cloud-infrastructure-tf-state-dev`
- Prod: `hybrid-cloud-infrastructure-tf-state-prod`

## No Local Access

All plan/apply runs via GitHub Actions only. No local AWS credentials.
