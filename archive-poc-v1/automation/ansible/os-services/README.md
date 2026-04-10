# OS Services - System Maintenance Playbooks

This directory contains Ansible playbooks for routine system monitoring, health checks, and emergency user management.

**NOTE:** System updates are intentionally NOT automated to prevent unintended risks from kernel version changes, dependency conflicts, or application-specific package requirements. Updates should be manually planned and tested.

## Playbooks Overview

### 1. Emergency User Creation (`01-emergency-user.yml`)
Creates a DR/backup emergency user for when IPA domain admin is unreachable.

**Features:**
- Creates `veeam_emergency` user with sudo access
- Generates strong random password or accepts custom password
- Configures SSH access
- Creates audit trail with user info file

**Usage:**
```bash
# Interactive (prompts for password)
ansible-playbook -i inventory 01-emergency-user.yml

# With custom password
ansible-playbook -i inventory 01-emergency-user.yml -e "emergency_password='YourSecurePassword123!'"
```

**IMPORTANT:** Save the displayed password securely! It's also saved in `/root/emergency_user_veeam_emergency_info.txt`

### 2. Disk Space Monitoring (`02-disk-space-check.yml`)
Monitors disk usage and alerts on thresholds.

**Features:**
- Checks all filesystems against thresholds (default: 60% warning, 80% critical)
- Identifies largest directories on critical filesystems
- Finds old log files (>30 days, >100MB)
- Generates detailed reports

**Usage:**
```bash
# Default thresholds (60% warning, 80% critical)
ansible-playbook -i inventory 02-disk-space-check.yml

# Custom thresholds
ansible-playbook -i inventory 02-disk-space-check.yml -e "warning_threshold=70 critical_threshold=85"
```

### 3. System Health Check (`03-system-health-check.yml`)
Comprehensive system health assessment.

**Features:**
- System resources (CPU, memory, load)
- Service status (SSH, time sync, firewall)
- Network connectivity (gateway, DNS)
- Security checks (SELinux, failed logins)
- Storage health (disk errors, inode usage)
- Process health (zombies, top consumers)
- Available updates

**Usage:**
```bash
ansible-playbook -i inventory 03-system-health-check.yml
```

Report saved to: `/tmp/health_report_<hostname>_<date>.txt`

### 4. Combined Health & Maintenance (`04-combined-health-maintenance.yml`)
Quick health check and optional maintenance in one run.

**Features:**
- Combines disk, health, network, and security checks
- Optional system updates
- Single comprehensive report
- Fast execution for routine checks

**Usage:**
```bash
# Health check only (no updates)
ansible-playbook -i inventory 04-combined-health-maintenance.yml

# Health check + perform updates
ansible-playbook -i inventory 04-combined-health-maintenance.yml -e "perform_updates=true"

# With custom disk thresholds
ansible-playbook -i inventory 04-combined-health-maintenance.yml -e "warning_threshold=70 critical_threshold=85"
```

## Recommended Schedules

### Daily
```bash
# Quick health check
ansible-playbook -i inventory 04-combined-health-maintenance.yml
```

### Weekly
```bash
# Full health check
ansible-playbook -i inventory 03-system-health-check.yml

# Disk space monitoring
ansible-playbook -i inventory 02-disk-space-check.yml
```

### One-time Setup
```bash
# Create emergency user
ansible-playbook -i inventory 01-emergency-user.yml
```

## Cron Automation Examples

Add to your Ansible control node or use cron on individual servers:

```bash
# Daily health check at 2 AM
0 2 * * * cd /opt/workspace/DC-K8s/03-AUTOMATION/ansible-playbooks/os-services && ansible-playbook -i inventory 04-combined-health-maintenance.yml >> /var/log/ansible-health.log 2>&1

# Weekly disk check on Sundays at 3 AM
0 3 * * 0 cd /opt/workspace/DC-K8s/03-AUTOMATION/ansible-playbooks/os-services && ansible-playbook -i inventory 02-disk-space-check.yml >> /var/log/ansible-disk.log 2>&1
```

## Inventory Setup

Create an inventory file or use existing one:

```ini
# inventory/hosts.ini
[all_vms]
vm1.example.com
vm2.example.com
vm3.example.com

[web_servers]
web1.example.com
web2.example.com

[database_servers]
db1.example.com
```

Then run:
```bash
ansible-playbook -i inventory/hosts.ini 03-system-health-check.yml
```

## Variables Reference

### Disk Monitoring
- `warning_threshold`: Warning percentage (default: 60)
- `critical_threshold`: Critical percentage (default: 80)

### Combined Maintenance
- `perform_updates`: Run system updates (default: false)
- `skip_kernel_updates`: Skip kernel updates (default: true)
- `warning_threshold`: Disk warning % (default: 60)
- `critical_threshold`: Disk critical % (default: 80)

## Best Practices

1. **Test playbooks** on non-production systems first
2. **Monitor reports** regularly in `/tmp/`
3. **Secure emergency user** password in password manager
4. **Manually plan and test system updates** - do not automate them
5. **Review health reports** to identify systems needing manual updates

## Troubleshooting

**Q: Emergency user creation fails**
A: Check if user already exists: `id veeam_emergency`

**Q: Disk check shows false positives**
A: Adjust thresholds with `-e "warning_threshold=X critical_threshold=Y"`

**Q: Reports not generated**
A: Check `/tmp/` permissions and disk space

## Security Notes

- Emergency user has **NOPASSWD sudo** - secure the password properly
- All reports contain sensitive system information - restrict access
- Review `/var/log/secure` for unexpected emergency user logins
- Consider using Ansible Vault for storing emergency user password

## Support

For issues or questions, check the main project README or contact your system administrator.
