# AWS Infrastructure

All AWS cloud infrastructure code and documentation.

## Structure

```
aws/
├── terraform/              # IaC for AWS resources
│   ├── vpc/                # VPC, subnets, routing
│   ├── eks/                # EKS cluster
│   ├── s3-backend/         # Terraform state storage
│   └── modules/            # Reusable AWS modules
├── ansible/                # AWS resource configuration
├── docs/                   # AWS documentation
│   ├── architecture/
│   ├── configuration-guides/
│   └── decisions/
├── manual-configs/         # Console exports, screenshots
├── troubleshooting-cases/  # AWS troubleshooting docs
└── scripts/
    ├── bash/
    └── python/
```

## Getting Started

```bash
# Configure AWS CLI
aws configure

# Initialize Terraform backend first
cd terraform/s3-backend
terraform init && terraform apply
```

## Resources

| Resource | Directory | Status |
|----------|-----------|--------|
| VPC | terraform/vpc/ | Planned |
| EKS | terraform/eks/ | Planned |
| S3 Backend | terraform/s3-backend/ | Planned |
