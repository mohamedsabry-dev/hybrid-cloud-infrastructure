# CI/CD Infrastructure

CI/CD pipeline configurations for Jenkins and GitHub Actions.

## Structure

```
cicd/
├── jenkins/
│   ├── terraform/          # Jenkins deployment
│   ├── ansible/            # Jenkins config
│   ├── pipelines/          # Jenkinsfiles
│   │   ├── infrastructure/ # Infra pipelines
│   │   ├── applications/   # App pipelines
│   │   └── security-scans/ # Security pipelines
│   ├── shared-libraries/   # Groovy libraries
│   ├── docs/
│   ├── troubleshooting-cases/
│   └── manual-configs/
│
└── github-actions/
    ├── workflows/          # GitHub Actions YAML
    │   ├── terraform-ci.yml
    │   ├── ansible-lint.yml
    │   └── security-scan.yml
    ├── docs/
    └── scripts/
```

## Pipeline Strategy

| Pipeline | Tool | Purpose |
|----------|------|---------|
| Terraform CI | GitHub Actions | PR validation |
| Terraform Apply | Jenkins | Infrastructure deployment |
| Ansible Lint | GitHub Actions | Playbook validation |
| Security Scan | Both | Vulnerability scanning |

## Jenkins

On-premises Jenkins for:
- Sensitive deployments
- On-prem resource access
- Complex workflows

## GitHub Actions

Cloud-based for:
- PR validation
- Linting
- Quick feedback

## Getting Started

```bash
# Deploy Jenkins
cd jenkins/terraform
terraform init && terraform apply

# Install GitHub Actions workflows
cp github-actions/workflows/*.yml ../.github/workflows/
```
