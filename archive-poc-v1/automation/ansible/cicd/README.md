# CI/CD Infrastructure Playbooks

## Overview
Ansible playbooks for managing CI/CD infrastructure and automation platforms.

**Target VMs:**
- jenkins-master: 10.0.20.196
- (Future: Jenkins agents, GitLab runners, etc.)

## Playbook Categories

### Installation & Setup
- Jenkins master installation
- Plugin management
- Agent node configuration
- Build tools installation (Maven, Gradle, npm, etc.)

### Configuration Management
- Jenkins job DSL automation
- Pipeline library updates
- Credentials management (integrate with Vault)
- Webhook configuration

### Integration
- Git repository integration
- Container registry configuration
- Kubernetes deployment integration
- Slack/notification setup
- Vault secrets integration

### Security
- User access control
- Role-based permissions
- Secret scanning configuration
- Build artifact signing

### Operations & Maintenance
- Backup Jenkins home
- Plugin updates
- Build cleanup (old artifacts)
- Performance tuning
- Log management

## Naming Convention
```
cicd-[NN]-[platform]-[description].yml

Examples:
- cicd-01-install-jenkins.yml
- cicd-02-configure-plugins.yml
- cicd-03-setup-vault-integration.yml
- cicd-04-backup-jenkins-home.yml
- cicd-05-update-pipeline-libraries.yml
- cicd-06-configure-k8s-deploy.yml
```

## Usage
```bash
# Run against Jenkins master
ansible-playbook -i ../inventory cicd-01-install-jenkins.yml

# Run against all CI/CD nodes
ansible-playbook -i ../inventory cicd-XX-playbook.yml --limit cicd_servers

# Dry run for testing
ansible-playbook -i ../inventory cicd-XX-playbook.yml --check
```

## Important Notes
- Jenkins updates require maintenance window
- Always backup before plugin updates
- Test pipeline changes in non-production job first
- Coordinate with development teams for build environment changes
- Store credentials in Vault, not Jenkins directly

## Integration Points
- **Source Control:** Git repositories (GitHub/GitLab)
- **Artifact Storage:** Nexus/Artifactory or NAS VM
- **Container Registry:** Harbor or Docker Hub
- **Secrets Management:** HashiCorp Vault
- **Deployment Target:** Kubernetes cluster
- **Notifications:** Slack, email, webhooks

## Build Agent Management
When adding build agents:
- Ensure proper network access to Jenkins master
- Install required build tools per project needs
- Configure resource limits (CPU, memory)
- Set up proper cleanup policies

## Related Documentation
- [Vault Playbooks](../vault/) - Vault cluster setup
- [IPA Playbooks](../ipa/) - Identity management
- [Monitor Playbooks](../monitor/) - Prometheus setup

## Security Best Practices
- Never store plain-text credentials
- Use Vault for secret injection
- Implement build approval gates
- Scan artifacts for vulnerabilities
- Audit build history regularly
- Restrict who can modify jobs
