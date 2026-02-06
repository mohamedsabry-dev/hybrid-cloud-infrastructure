# Terraform Infrastructure

## Directory Structure

```
terraform/
├── dev/                 # Dev environment (018571635409)
│   ├── aws/
│   │   └── iam/         # IAM roles and policies
│   └── proxmox/         # (future)
├── prod/                # Prod environment (969041180300)
│   ├── aws/
│   │   └── iam/         # IAM roles and policies
│   └── proxmox/         # (future)
└── guide.txt            # Quick command reference
```

## AWS Profiles

| Profile | Account | Purpose |
|---------|---------|---------|
| `plan-cross-dev` | Dev (018571635409) | Local plan/apply for dev |
| `prod-readonly` | Prod (969041180300) | Local plan for prod (read-only) |

## Commands

### Dev Modules
```bash
AWS_PROFILE=plan-cross-dev terraform plan
AWS_PROFILE=plan-cross-dev terraform apply
```

### Prod Modules
```bash
# Plan only (read-only access)
AWS_PROFILE=prod-readonly terraform plan -lock=false

# Apply via CI/CD only (push to main branch)
```

## CI/CD

- **Dev**: Push to `dev` branch triggers `dev-iam.yml` workflow
- **Prod**: Push to `main` branch triggers `prod-iam.yml` workflow

## Bootstrap

CloudFormation stacks in each account:
- `dev/aws/bootstrap-dev.yaml` → dev-bootstrap stack
- `prod/aws/bootstrap-prod.yaml` → prod-bootstrap stack
