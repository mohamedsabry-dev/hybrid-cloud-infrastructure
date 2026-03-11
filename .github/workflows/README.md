# GitHub Actions Workflows

## Branch Flow

| Change Type | Path |
|-------------|------|
| Infrastructure | `dev` → `prod` → `main` |
| IAM/Security | `dev` → `dev-security` → `prod-security` → `prod` → `main` |

> `prod` is always the last stage before `main`

## Workflows

### Combined Workflows (Multi-Job)
| Workflow | Jobs | Purpose |
|----------|------|---------|
| `dev-golden-full-setup` | 2 | Create golden VM + LXC templates |
| `dev-ansible-full-setup` | 4 | Deploy Ansible LXC + Deploy Key + Setup |
| `dev-freeipa-full-setup` | 2 | Deploy FreeIPA VM + Service Install |
| `dev-local-runner-full-setup` | 3 | Deploy Runner LXC + GH Runner + Tools |
| `dev-k8s-full-setup` | 2 | Deploy K8s Masters + Workers |
| `dev-nginx-full-setup` | 1 | Deploy Nginx (ready for expansion) |
| `dev-vault-full-setup` | 1 | Deploy Vault (ready for expansion) |

### AWS
| Workflow | Branch | Purpose |
|----------|--------|---------|
| `dev-aws-secrets` | dev | Deploy AWS secrets |
| `dev-aws-iam` | dev-security | Deploy IAM roles/policies |

### Production
| Workflow | Branch | Purpose |
|----------|--------|---------|
| `prod-*` | prod / prod-security | Same as dev, for production |

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

## LXC SSH Key Injection Limitation

### The Problem
The bpg/proxmox Terraform provider's **clone method** for LXC containers does NOT support SSH key injection via the `user_account {}` block. Keys specified during clone are silently ignored.

### Solutions

**Option 1: Template Conversion (Recommended)**

Convert your golden LXC to a proper template file using vzdump:

```bash
# 1. Stop the container
pct stop 9001

# 2. Create backup
vzdump 9001 --compress gzip --storage local --mode stop

# 3. Move to template directory
mv /var/lib/vz/dump/vzdump-lxc-9001-*.tar.gz /mnt/pve/nas-iso/template/cache/rocky-9-lxc-golden.tar.gz

# 4. Delete source container
pct destroy 9001
```

Then in Terraform, use `operating_system { template_file_id }` instead of `clone {}`:

```hcl
operating_system {
  template_file_id = "nas-iso:vztmpl/rocky-9-lxc-golden.tar.gz"
  type             = "centos"
}

initialization {
  user_account {
    keys     = var.ssh_public_keys  # Works with template method
    password = var.root_password
  }
}
```

**Option 2: Post-Creation SSH Injection**

Keep using clone method but inject keys via workflow using sshpass:

```yaml
- name: Inject SSH Keys
  run: |
    sshpass -p "${ROOT_PASSWORD}" ssh root@<LXC_IP> \
      "mkdir -p ~/.ssh && echo '${SSH_PUBLIC_KEY}' >> ~/.ssh/authorized_keys"
```

### Which to Choose?

| Approach | Pros | Cons |
|----------|------|------|
| Template Conversion | Clean, native support, keys work at boot | Extra conversion step |
| Post-Creation SSH | Works with existing clones | Requires password auth initially |

**We use Template Conversion** for all LXCs to ensure SSH keys are available immediately at first boot.

## Multi-Job Workflows with Independent Locks

### Pattern
Combined workflows have multiple jobs, each with its own lock. Jobs should skip independently without blocking downstream jobs.

### The Problem (Bug)
When using this condition pattern:
```yaml
if: ${{ (needs.job.result == 'success' || needs.job.result == 'skipped') && vars.LOCK != 'true' }}
```

**GitHub's default behavior:** When a job is skipped, downstream jobs with `needs:` are **automatically skipped** without evaluating their `if` condition.

```
Job 1 LOCKED (skipped)
       |
    [GitHub sees skip]
       |
    [Auto-skip Job 2 - if condition NEVER evaluated]
       |
    [Auto-skip Job 3 - if condition NEVER evaluated]

Result: All jobs skipped, even with their locks = false
```

### The Solution
Use `always()` to force condition evaluation:
```yaml
if: ${{ always() && needs.job.result != 'failure' && needs.job.result != 'cancelled' && vars.LOCK != 'true' }}
```

**How it works:**
- `always()` - Forces GitHub to evaluate the `if` condition regardless of upstream status
- `!= 'failure'` - Don't run if previous job failed
- `!= 'cancelled'` - Don't run if workflow was cancelled
- `vars.LOCK != 'true'` - Don't run if this job's lock is enabled

```
Job 1 LOCKED (skipped)
       |
Job 2: always() forces if evaluation
       |
    Check: result != 'failure' -> true
    Check: result != 'cancelled' -> true
    Check: vars.LOCK != 'true' -> true (if unlocked)
       |
    Job 2 RUNS (or skips if its own lock is true)
```

### Behavior Summary

| Previous Job | Next Job (unlocked) |
|--------------|---------------------|
| Success | Runs |
| Skipped (locked) | Runs |
| Failed | Does NOT run |
| Cancelled | Does NOT run |

### Lock Variables
All dev workflows use lock variables to skip jobs:
- `DEV_INFRA_*_LOCK` - Infrastructure deployment jobs
- `DEV_SVC_*_LOCK` - Service setup jobs

Set to `true` to skip, `false` to run.

## Writing New Workflows

See **[workflow-guide.txt](workflow-guide.txt)** for:
- Step-by-step templates
- Comment format blocks
- Common mistakes
- Checklists
