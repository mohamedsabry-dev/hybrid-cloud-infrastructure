# GitHub Actions Workflows

## Branch Flow

| Change Type | Path |
|-------------|------|
| Infrastructure | `dev` → `prod` → `main` |
| IAM/Security | `dev` → `dev-security` → `prod-security` → `prod` → `main` |

> `prod` is always the last stage before `main`

## Workflows

| Workflow | Branch | Purpose |
|----------|--------|---------|
| `dev-proxmox-golden-image` | dev | Create golden image VM |
| `dev-proxmox-golden-lxc-template` | dev | Create golden LXC template |
| `dev-proxmox-test-clones` | dev | Test VM from template |
| `dev-secrets` | dev | Deploy AWS secrets |
| `dev-iam` | dev-security | Deploy IAM roles/policies |
| `prod-*` | prod / prod-security | Same as dev, for production |

## Writing New Workflows

See **[workflow-guide.txt](workflow-guide.txt)** for:
- Step-by-step templates
- Comment format blocks
- Common mistakes
- Checklists
