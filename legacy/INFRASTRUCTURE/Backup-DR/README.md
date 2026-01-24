================================================================================
BACKUP & DISASTER RECOVERY
Platform-Level Backup Services and Emergency Procedures
================================================================================
Version: 2.0
Last Updated: 2026-01-03
Purpose: Veeam backup configuration, emergency shutdown automation, and recovery procedures

================================================================================
OVERVIEW
================================================================================

This folder contains platform-level backup and disaster recovery documentation,
focusing on Veeam backup services, emergency shutdown automation, and recovery procedures.

**Note:** Infrastructure-level DR (ESXi failover) is documented separately.
See [Infrastructure Layer DR](../../01-Infrastructure-Layer/DR/) for:
- ESXi failover procedures
- VM startup/shutdown orchestration
- Cold standby DR activation

================================================================================
DOCUMENTS IN THIS FOLDER
================================================================================

### Core Backup Documentation

**[01-Backup-Strategy.md](01-Backup-Strategy.md)** - Veeam Architecture
- Dual Veeam setup (Outer vs Inner instances)
- Backup repository configuration
- vCenter built-in backups
- Performance optimization settings
- Email notifications

**[02-Emergency-Shutdown.md](02-Emergency-Shutdown.md)** - Power-Loss Protection
- Battery monitoring daemon (BatteryMonitor.ps1)
- Emergency shutdown orchestration (EmergencyLabShutdown.ps1)
- Phase-by-phase shutdown sequence
- Veeam job termination (hard kill)
- Testing and validation procedures

**[03-Recovery-Procedures.md](03-Recovery-Procedures.md)** - Restore Operations
- Inner layer recovery (via vCenter + domain user)
- Outer layer recovery (via standalone ESXi)
- Emergency scenarios (using veeam_emergency user)
- Step-by-step restore workflows
- Special scenarios (NAS failure, vCenter failure, etc.)

### Reference Documentation

**[04-Design-Decisions.md](04-Design-Decisions.md)** - Architectural Rationale
- Why standalone ESXi for outer layer backups?
- Why no backup copy jobs?
- Why hard kill Veeam jobs during DR?
- Why 75% battery threshold?
- Why internal network (10.0.20.x)?
- Why not use vCenter snapshots?
- Why two Veeam servers?

**[05-Configuration-Reference.md](05-Configuration-Reference.md)** - Technical Specifications
- IP addressing scheme
- Backup job schedules
- File paths and script locations
- PowerShell requirements
- Veeam performance settings
- Quick reference tables

================================================================================
BACKUP ARCHITECTURE SUMMARY
================================================================================

## Dual Veeam Architecture

**Outer Veeam (Windows Host):**
- Backs up: Inner layer application VMs
  - K8s Master + 3 Workers
  - Vault cluster (3 nodes)
  - Jenkins, Ansible, Monitor
- Total: 10 VMs
- Connection: via vCenter (10.0.20.89)
- Repository: Windows Host (D:\Veeam_Backups\)
- Schedule: Daily automated

**Inner Veeam (10.0.20.195):**
- Backs up: Outer layer infrastructure VMs
  - IPA, pfSense, NAS
  - vCenter, Production ESXi, DR ESXi
  - Veeam Inner itself
- Total: 7 VMs (3 automated daily, 4 manual)
- Connection: Standalone ESXi Master (10.0.20.100) - NOT vCenter
- Repository: NAS (/mnt/backups/veeam/)
- Schedule: Daily for critical VMs, manual for others

**Why Two Veeam Servers?**
- Veeam Community Edition: 10 VM limit per instance
- Total VMs: 17 (requires 2 instances)
- Cross-layer protection (each backs up the other's layer)

See [01-Backup-Strategy.md](01-Backup-Strategy.md) for details.

================================================================================
EMERGENCY SHUTDOWN SYSTEM
================================================================================

## Power-Loss Protection Workflow

```
Power Outage Detected
    ↓
Battery ≤ 75% (discharging)
    ↓
Emergency Shutdown Triggered
    ↓
Phase 2: Kill Veeam jobs (< 1 min)
    ↓
Phase 3: Shutdown nested ESXi (3 min)
    ↓
Phase 4: Shutdown master ESXi (3 min)
    ↓
Phase 5: VMware Workstation fallback (if needed)
    ↓
Phase 6: Shutdown laptop
```

**Total Time:** 10-13 minutes
**Battery Runtime at 75%:** 15-20 minutes
**Safety Margin:** 5-7 minutes

See [02-Emergency-Shutdown.md](02-Emergency-Shutdown.md) for complete details.

================================================================================
RECOVERY PROCEDURES
================================================================================

## Three Recovery Paths

**Path 1: Normal Operations (Domain Online)**
- Use when: Restoring inner layer VMs, IPA is online
- Connection: Outer Veeam → vCenter → Production ESXi
- User: veeam@home.lab (FreeIPA domain user)
- Use case: Routine VM restores

**Path 2: Outer Layer Recovery (Standalone ESXi)**
- Use when: Restoring infrastructure VMs (IPA, vCenter, NAS, etc.)
- Connection: Inner Veeam → Standalone ESXi Master (NOT vCenter)
- User: veeam_emergency (local user with password)
- Use case: Infrastructure-level failures

**Path 3: Emergency Recovery (Domain Offline)**
- Use when: Restoring inner VMs but IPA is down
- Connection: Outer Veeam → vCenter → Production ESXi
- User: veeam_emergency (local user with SSH key)
- Use case: IPA failure, domain unavailable

See [03-Recovery-Procedures.md](03-Recovery-Procedures.md) for step-by-step procedures.

================================================================================
USER ACCOUNTS & AUTHENTICATION
================================================================================

**Domain User (Normal Operations):**
- Account: veeam@home.lab (FreeIPA domain)
- Purpose: Automated daily backups of inner layer VMs
- Auth: Passwordless sudo
- Usage: When domain is available

**Emergency User (DR Scenarios):**
- Account: veeam_emergency (local user)
- Inner Layer: SSH key authentication (key in Vault)
- Outer Layer: Password authentication
- Purpose: Backup access when domain is unavailable
- Deployment: Via Ansible playbook

See [User Accounts](../Identity/02-User-Accounts.md) for complete details.

================================================================================
QUICK START GUIDES
================================================================================

## For Backup Monitoring

1. Review [01-Backup-Strategy.md](01-Backup-Strategy.md) for schedules
2. Check email notifications for job status
3. Verify backup completion in Veeam console

## For Emergency Shutdown Testing

1. Read [02-Emergency-Shutdown.md](02-Emergency-Shutdown.md)
2. Run dry-run tests (Scripts/Dry Run/)
3. Schedule full DR drill

## For VM Recovery

1. Identify failure scenario
2. Choose recovery path (see above)
3. Follow [03-Recovery-Procedures.md](03-Recovery-Procedures.md)
4. Verify services post-recovery

================================================================================
DESIGN DECISIONS SUMMARY
================================================================================

All major architectural decisions are documented with full rationale:

1. **Standalone ESXi Connection** - Eliminates circular dependency
2. **No Backup Copy Jobs** - Rejected for complexity vs benefit
3. **Hard Kill Veeam Jobs** - Immediate stop during DR
4. **75% Battery Threshold** - Balances safety and practicality
5. **Internal Network** - Survives external network loss
6. **Manual Snapshots Only** - Avoids Veeam conflicts

See [04-Design-Decisions.md](04-Design-Decisions.md) for full explanations.

================================================================================
RELATED DOCUMENTATION
================================================================================

### Platform Layer
- [Identity Management](../Identity/) - User accounts and authentication
- [Secrets Management](../Secrets-Management/) - Vault integration
- [Monitoring](../Monitoring/) - Backup monitoring

### Infrastructure Layer
- [Infrastructure DR](../../01-Infrastructure-Layer/DR/) - ESXi failover
- [Compute Resources](../../01-Infrastructure-Layer/Compute/) - Resource allocation
- [Network Architecture](../../01-Infrastructure-Layer/Network/) - Network design
- [Storage Architecture](../../01-Infrastructure-Layer/Storage/) - Storage configuration

### Scripts
- Emergency shutdown scripts in [01-Infrastructure-Layer/DR/Scripts/](../../01-Infrastructure-Layer/DR/Scripts/)

================================================================================
DOCUMENT INDEX
================================================================================

1. [01-Backup-Strategy.md](01-Backup-Strategy.md) - Veeam architecture and configuration
2. [02-Emergency-Shutdown.md](02-Emergency-Shutdown.md) - Power-loss protection system
3. [03-Recovery-Procedures.md](03-Recovery-Procedures.md) - Restore and recovery operations
4. [04-Design-Decisions.md](04-Design-Decisions.md) - Architectural rationale
5. [05-Configuration-Reference.md](05-Configuration-Reference.md) - Technical specifications

**User Account Documentation:**
- [02-User-Accounts.md](../Identity/02-User-Accounts.md) - Located in Identity folder

================================================================================
NEXT STEPS
================================================================================

- Schedule quarterly DR drills
- Test emergency shutdown system monthly
- Verify backup email notifications weekly
- Review and update documentation after changes

================================================================================
END OF BACKUP & DR GUIDE
================================================================================
