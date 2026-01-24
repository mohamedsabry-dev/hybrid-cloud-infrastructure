# Tagging Strategy

Resource tagging standards for cost allocation, automation, and management.

## Required Tags

All resources MUST have these tags:

| Tag Key | Description | Example Values |
|---------|-------------|----------------|
| Environment | Deployment environment | prod, dr, dev |
| Service | Service/application name | vault, ipa, k8s |
| ManagedBy | How resource is managed | terraform, ansible, manual |
| Owner | Team/person responsible | devops, platform |
| Project | Project identifier | hybrid-cloud |

## Optional Tags

| Tag Key | Description | Example Values |
|---------|-------------|----------------|
| CostCenter | For billing allocation | infra-001 |
| Backup | Backup policy | daily, weekly, none |
| Compliance | Compliance requirements | pci, hipaa |
| CreatedDate | Creation timestamp | 2024-01-20 |

## Terraform Example

```hcl
locals {
  common_tags = {
    Environment = var.environment
    Service     = var.service_name
    ManagedBy   = "terraform"
    Owner       = "devops"
    Project     = "hybrid-cloud"
  }
}

resource "aws_instance" "example" {
  # ... configuration ...

  tags = merge(local.common_tags, {
    Name = "${var.environment}-${var.service_name}-instance"
  })
}
```

## VMware Labels

Apply same tagging via vSphere custom attributes or VM annotations.

## Kubernetes Labels

```yaml
metadata:
  labels:
    environment: prod
    service: web-api
    managed-by: helm
    owner: devops
```
