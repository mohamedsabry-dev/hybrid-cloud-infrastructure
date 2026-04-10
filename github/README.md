# GitHub Configuration

GitHub Actions workflows, deployment patterns, and runner setup documentation.

## Documents

| File | Description |
|------|-------------|
| [deployment-flow.md](deployment-flow.md) | End-to-end deployment flow with architecture diagram |
| [deployment-pattern.md](deployment-pattern.md) | Workflow patterns and conventions |
| [internal-runners-setup.md](internal-runners-setup.md) | Self-hosted runner setup for dev/prod |
| [repository-setup.md](repository-setup.md) | Repository configuration and branch strategy |
| [runner-mac-mini.md](runner-mac-mini.md) | Mac Mini runner setup for local execution |
| [variables-secrets.md](variables-secrets.md) | GitHub secrets and variables reference |

## Architecture Overview

```
GitHub Actions
     │
     ├── AWS-hosted runners (GitHub default)
     │   └── Terraform deployments to AWS
     │
     └── Self-hosted runners
         ├── Mac Mini (local workstation)
         └── Internal LXC runners (Proxmox)
             └── Ansible deployments to internal infra
```

## Quick Reference

### Runner Types

| Runner | Location | Purpose |
|--------|----------|---------|
| GitHub-hosted | AWS | Terraform AWS deployments |
| Mac Mini | Local | Workstation tasks |
| Internal LXC | Proxmox | Ansible to internal services |

### Branch Strategy

| Branch | Environment | Auto-deploy |
|--------|-------------|-------------|
| `main` | Production | No (manual) |
| `dev-*` | Development | Yes |

## Related

- [GitHub Actions Workflows](../.github/workflows/)
- [Deployment Docs](../deployment-docs/)
