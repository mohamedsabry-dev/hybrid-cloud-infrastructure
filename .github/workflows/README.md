# GitHub Actions Workflows

## Branch Flow

| Change Type | Path |
|-------------|------|
| Infrastructure | `dev` → `prod` → `main` |
| IAM/Security | `dev` → `dev-security` → `prod-security` → `prod` → `main` |

> `prod` is always the last stage before `main`

## Workflows

### Day 0 - Templates
| Workflow | Branch | Purpose |
|----------|--------|---------|
| `dev-golden-vm` | dev | Create golden image VM template |
| `dev-golden-lxc` | dev | Create golden LXC template |

### Day 0 - Control Plane
| Workflow | Branch | Purpose |
|----------|--------|---------|
| `dev-freeipa` | dev | Deploy FreeIPA VM (identity/domain) |
| `dev-ansible` | dev | Deploy Ansible LXC (configuration mgmt) |

### AWS
| Workflow | Branch | Purpose |
|----------|--------|---------|
| `dev-secrets` | dev | Deploy AWS secrets |
| `dev-iam` | dev-security | Deploy IAM roles/policies |

### Production
| Workflow | Branch | Purpose |
|----------|--------|---------|
| `prod-*` | prod / prod-security | Same as dev, for production |

## Writing New Workflows

See **[workflow-guide.txt](workflow-guide.txt)** for:
- Step-by-step templates
- Comment format blocks
- Common mistakes
- Checklists
