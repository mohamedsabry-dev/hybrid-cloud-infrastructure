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

**Used by:** `prod-local-runner-full-setup.yml` workflow

## When it runs

Invoked by `{env}-local-runner-full-setup.yml` after the runner LXC is
provisioned. Uses the bootstrap inventory (IP + root + SSH key) because the
runner LXC is configured BEFORE FreeIPA enrollment.

Manual re-run: executed via the workflow, not via ad-hoc command. If a new
tool is added to this playbook, trigger the workflow instead of running
ansible-playbook by hand.

## Notes

- Runner registration is handled by the workflow, not Ansible
- AWS CLI is needed for OIDC authentication in workflows
- Additional tools can be added to this playbook as needed
