# OS Services - Baseline Configuration & Hardening

This directory contains Ansible playbooks for **baseline OS configuration** that applies to **ALL VMs** regardless of their specific role (K8s, IPA, Vault, etc.).

## Purpose

**os-services** provides the horizontal layer of configuration that every VM needs:
- Initial OS setup (NTP, emergency users)
- Security hardening after IPA integration
- Ongoing operations and health monitoring

This is separate from service-specific folders (IPA, Vault, CICD) which provide vertical service integration.

---

## Directory Structure

```
os-services/
├── baseline/              ← Initial OS setup for new VMs
├── security-hardening/    ← Sequential security lockdown (after IPA integration)
├── operations/            ← Day-2 operations and troubleshooting
└── guides/                ← Documentation and procedures
```

---

## 1. Baseline Configuration

**Purpose**: Essential OS configuration applied to new VMs during initial setup.

### Files:
- **[configure-ntp-to-ipa.yml](baseline/configure-ntp-to-ipa.yml)** - Configure all VMs to sync time with IPA server
- **[create-emergency-user.yml](baseline/create-emergency-user.yml)** - Create break-glass emergency user (veeam_emergency)

### Execution Order:
```bash
# Run on newly provisioned VMs
ansible-playbook -i ../inventory baseline/configure-ntp-to-ipa.yml
ansible-playbook -i ../inventory baseline/create-emergency-user.yml
```

### When to Use:
- After VM provisioning
- Before IPA client enrollment
- Part of standard VM baseline

---

## 2. Security Hardening

**Purpose**: Sequential security lockdown performed **AFTER** VMs are integrated with IPA.

⚠️ **IMPORTANT**: These playbooks remove local users and enforce IPA-only authentication. Run them in order AFTER confirming IPA authentication works.

### Files (run in sequence):

1. **[01-audit-local-users.yml](security-hardening/01-audit-local-users.yml)**
   - Audits existing local users before deletion
   - Generates report of users to be removed
   - **Run first** to review what will be deleted

2. **[02-delete-local-users.yml](security-hardening/02-delete-local-users.yml)**
   - Removes local users (except system users)
   - Forces IPA-only authentication
   - ⚠️ Ensure IPA auth works before running!

3. **[03-retire-legacy-ansible.yml](security-hardening/03-retire-legacy-ansible.yml)**
   - Removes legacy Ansible automation accounts
   - Cleans up old service accounts

4. **[04-cleanup-home-dirs.yml](security-hardening/04-cleanup-home-dirs.yml)**
   - Removes home directories of deleted users
   - Frees up disk space

5. **[05-lock-ssh-config.yml](security-hardening/05-lock-ssh-config.yml)**
   - Hardens SSH configuration
   - Disables password authentication
   - Enforces key-based authentication only

6. **[06-wipe-root-keys.yml](security-hardening/06-wipe-root-keys.yml)**
   - Removes root SSH keys
   - Forces certificate-based authentication via Vault

### Execution Order:
```bash
# PREREQUISITE: Verify IPA authentication works for all users!
# Test: ssh user@host (using IPA credentials)

# Run security hardening in sequence:
ansible-playbook -i ../inventory security-hardening/01-audit-local-users.yml
# Review the audit report before proceeding!

ansible-playbook -i ../inventory security-hardening/02-delete-local-users.yml
ansible-playbook -i ../inventory security-hardening/03-retire-legacy-ansible.yml
ansible-playbook -i ../inventory security-hardening/04-cleanup-home-dirs.yml
ansible-playbook -i ../inventory security-hardening/05-lock-ssh-config.yml
ansible-playbook -i ../inventory security-hardening/06-wipe-root-keys.yml
```

### When to Use:
- After successful IPA client enrollment
- After verifying IPA users can authenticate
- Part of security compliance process
- Before production deployment

---

## 3. Operations

**Purpose**: Day-2 operations, troubleshooting, and ongoing maintenance.

### Files:
- **[combined-health-checks.yml](operations/combined-health-checks.yml)** - Comprehensive system health checks
- **[fix-ntp-sync.yml](operations/fix-ntp-sync.yml)** - Fix NTP synchronization issues

### Usage:
```bash
# Run health checks
ansible-playbook -i ../inventory operations/combined-health-checks.yml

# Fix NTP issues
ansible-playbook -i ../inventory operations/fix-ntp-sync.yml
```

### When to Use:
- Regular health monitoring (daily/weekly)
- Troubleshooting time sync issues
- Audit and compliance checks

---

## 4. Guides

**Purpose**: Documentation and procedure guides for manual operations.

### Files:
- **[veeam-backup-user-setup.txt](guides/veeam-backup-user-setup.txt)** - Complete procedure for Veeam emergency backup user setup

---

## Complete VM Lifecycle Workflow

### Phase 1: Initial Provisioning
1. Provision VM (OS installation)
2. Run [baseline/configure-ntp-to-ipa.yml](baseline/configure-ntp-to-ipa.yml)
3. Run [baseline/create-emergency-user.yml](baseline/create-emergency-user.yml)

### Phase 2: IPA Integration
4. Enroll VM as IPA client (see `../IPA/` folder)
5. Verify IPA authentication works

### Phase 3: Security Hardening
6. Run security-hardening playbooks 01-06 in sequence
7. Verify only IPA users can authenticate

### Phase 4: Operations
8. Run regular health checks
9. Apply fixes as needed

---

## Integration with Other Services

### IPA Integration:
- **Before**: Run baseline configuration
- **After**: IPA provides centralized authentication
- **Then**: Run security hardening to enforce IPA-only auth

### Vault Integration:
- **After**: Security hardening 06 (wipe root keys)
- **Vault provides**: SSH certificate signing
- **Result**: Certificate-based SSH authentication

### CICD Integration:
- **CICD requires**: VMs to have baseline config complete
- **CICD uses**: Vault SSH certificates for automation

---

## Best Practices

1. **Test on non-production first**: Always test playbooks on dev/test VMs
2. **Backup before hardening**: Take VM snapshots before security lockdown
3. **Verify IPA auth**: Ensure IPA authentication works before deleting local users
4. **Run audits first**: Review 01-audit output before proceeding with deletions
5. **Keep emergency user**: Never delete veeam_emergency (break-glass access)
6. **Monitor health regularly**: Schedule health checks via cron

---

## Security Notes

⚠️ **CRITICAL WARNINGS**:

1. **Local User Deletion**: After running [02-delete-local-users.yml](security-hardening/02-delete-local-users.yml), only IPA users can authenticate. If IPA is down and you don't have veeam_emergency credentials, you'll lose access to VMs.

2. **Emergency User**: The veeam_emergency user has NOPASSWD sudo. Store credentials securely in a password manager.

3. **SSH Hardening**: After [05-lock-ssh-config.yml](security-hardening/05-lock-ssh-config.yml), password authentication is disabled. Ensure SSH keys are properly configured.

4. **Root Key Removal**: After [06-wipe-root-keys.yml](security-hardening/06-wipe-root-keys.yml), root SSH access requires Vault certificates. Ensure Vault integration is working.

---

## Troubleshooting

### Can't login after security hardening:
- Use veeam_emergency user for break-glass access
- Check IPA server is reachable: `ping ipa.home.lab`
- Verify IPA client enrollment: `ipa-client-install --uninstall` then re-enroll

### NTP sync issues:
- Run [operations/fix-ntp-sync.yml](operations/fix-ntp-sync.yml)
- Verify IPA server time: `ssh ipa.home.lab date`
- Check firewall rules: NTP port 123/udp

### Health check failures:
- Review generated reports in `/tmp/`
- Check specific service status: `systemctl status sshd`
- Verify network connectivity to IPA/Vault

---

## Variables Reference

### Baseline Configuration:
- `ipa_server`: IPA server FQDN (default: ipa.home.lab)
- `emergency_user`: Emergency username (default: veeam_emergency)
- `allowed_subnet`: SSH restriction subnet (default: 10.0.20.0/24)

### Security Hardening:
- `preserve_users`: List of users to keep (default: [root, veeam_emergency])
- `min_uid`: Minimum UID for user deletion (default: 1000)

### Operations:
- `warning_threshold`: Disk space warning % (default: 60)
- `critical_threshold`: Disk space critical % (default: 80)

---

## Support

For issues or questions:
- Review service-specific folders: `../IPA/`, `../vault/`, `../cicd/`
- Check [guides/](guides/) for detailed procedures
- Contact your system administrator

---

## Notes

**System updates are intentionally NOT automated** to prevent:
- Unintended risks from kernel version changes
- Dependency conflicts
- Application-specific package requirement issues

Updates should be manually planned, tested, and executed.
