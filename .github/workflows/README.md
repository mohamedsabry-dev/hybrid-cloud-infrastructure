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

### Service Workflows
| Workflow | Branch | Purpose |
|----------|--------|---------|
| `dev-svc-gh-local_runner` | dev | Setup GitHub Actions runner on LXC |

## GitHub Runner Setup (`dev-svc-gh-local_runner`)

### Prerequisites
1. **Secret**: `DEV_GH_RUNNER_TOKEN` - Fresh token from Settings > Actions > Runners
2. **Variables**: `DEV_GH_RUNNER_NAME`, `DEV_GH_RUNNER_LABELS`

### Troubleshooting

**Token expires quickly** - Generate a new token immediately before running the workflow.

**"Invalid configuration provided for token"** - Token is expired or invalid. Generate fresh token.

**"A runner exists with the same name"** - The workflow uses `--replace` flag to handle this automatically.

**Runner registers with wrong name (e.g., hostname instead of configured name)** - Use GitHub Actions expressions `${{ vars.VAR_NAME }}` directly in the command instead of shell variables `${VAR_NAME}` to ensure proper substitution through SSH.

**Orphaned config (runner exists locally but not on GitHub)** - The workflow automatically cleans config files (`.runner`, `.credentials`, `.credentials_rsaparams`) before configuring.

**"Session conflict" error** - Another runner with the same name is connected. Delete the conflicting runner from GitHub UI first.

**svc.sh "Must run from runner root"** - Run svc.sh from inside `/opt/actions-runner` directory: `cd /opt/actions-runner && ./svc.sh start`

### Manual Cleanup (if needed)
```bash
# On LXC (as root)
ssh root@10.0.63.20
cd /opt/actions-runner && ./svc.sh stop && ./svc.sh uninstall
su - runner -c "cd /opt/actions-runner && ./config.sh remove --token ANY_TOKEN"
# If config.sh remove fails, force cleanup:
rm -f /opt/actions-runner/.runner /opt/actions-runner/.credentials /opt/actions-runner/.credentials_rsaparams
```

## Writing New Workflows

See **[workflow-guide.txt](workflow-guide.txt)** for:
- Step-by-step templates
- Comment format blocks
- Common mistakes
- Checklists
