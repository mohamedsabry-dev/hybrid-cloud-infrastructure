# Naming Conventions

Standardized naming conventions for all infrastructure resources.

## General Format

```
{environment}-{service}-{resource}-{identifier}
```

## Environments

| Short | Full | Description |
|-------|------|-------------|
| prod | Production | Production environment |
| dr | Disaster Recovery | DR environment |
| dev | Development | Development/testing |

## Examples

### Virtual Machines

```
prod-ipa-server-01
prod-vault-node-01
prod-k8s-master-01
prod-k8s-worker-01
```

### AWS Resources

```
prod-hybrid-vpc
prod-hybrid-subnet-public
prod-hybrid-eks-cluster
prod-terraform-state-bucket
```

### Kubernetes

```
prod-web-deployment
prod-api-service
prod-db-configmap
```

## Tags/Labels

All resources must include:

| Tag | Example | Required |
|-----|---------|----------|
| Environment | prod | Yes |
| Service | vault | Yes |
| ManagedBy | terraform | Yes |
| Owner | devops | Yes |

## DNS Names

```
{service}.internal.local
vault.internal.local
ipa.internal.local
k8s-api.internal.local
```
