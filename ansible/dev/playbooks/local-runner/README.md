# Local Runner Playbooks

Playbooks for configuring GitHub Actions self-hosted runners.

## Playbooks

| Playbook | Purpose | Target |
|----------|---------|--------|
| `setup_tools.yml` | Install required tools (AWS CLI) | local_runners |

## Playbook Details

### setup_tools.yml

Installs tools required by the GitHub Actions runner:
- AWS CLI v2

**Used by:** `dev-local-runner-full-setup.yml` workflow

## Usage

```bash
# Run via workflow (automatic)
# Or manually:
ansible-playbook -i inventory/first_setup_inventory.ini playbooks/local-runner/setup_tools.yml
```

## Notes

- Runner registration is handled by the workflow, not Ansible
- AWS CLI is needed for OIDC authentication in workflows
- Additional tools can be added to this playbook as needed
