================================================================================
INFRASTRUCTURE DISASTER RECOVERY
ESXi Failover and VM Orchestration
================================================================================
Version: 2.0
Last Updated: 2026-01-03
Purpose: Infrastructure-level disaster recovery and VM lifecycle management

================================================================================
OVERVIEW
================================================================================

This folder contains infrastructure-level disaster recovery documentation focused
on ESXi host failover and VM startup/shutdown orchestration.

**Note:** Backup and recovery procedures have been moved to Platform Layer.
See [Platform Layer Backup-DR](../../02-Platform-Layer/Backup-DR/) for:
- Veeam backup configuration
- Emergency shutdown automation
- Recovery procedures
- User account management

================================================================================
DOCUMENTS IN THIS FOLDER
================================================================================

### Infrastructure DR Procedures

**[01-VM-Startup-Shutdown.md](01-VM-Startup-Shutdown.md)** - VM Lifecycle Management
- ESXi auto-startup configuration
- VM shutdown ordering and dependencies
- Timing and delay settings
- VMware Tools requirements

**[02-DR-Failover-Procedures.md](02-DR-Failover-Procedures.md)** - Cold Standby DR
- Production ESXi → DR ESXi failover
- DR ESXi activation procedures
- Failback from DR to Production
- RTO/RPO targets and testing

================================================================================
ARCHITECTURE SUMMARY
================================================================================

## Cold Standby DR Design

**Production ESXi (10.0.20.101):**
- Runs all application VMs (K8s, Vault, Jenkins, etc.)
- Backed by vCenter cluster
- Allocated: 30GB RAM

**DR ESXi (10.0.20.102):**
- Normally powered OFF (0GB memory usage)
- Activated only during Production ESXi failure
- Allocates same 30GB RAM when powered on
- Manual failover required (15-20 min RTO)

**Trade-offs:**
- ✅ Saves 30GB RAM for production workloads
- ✅ Enables 3 K8s workers instead of 2
- ❌ Manual failover (not automatic)
- ❌ 15-20 minute recovery time

See [Design Decisions](../../02-Platform-Layer/Backup-DR/06-Design-Decisions.md) for full rationale.

================================================================================
VM STARTUP/SHUTDOWN ORCHESTRATION
================================================================================

**ESXi Master Auto-Startup Order:**
1. IPA (60s delay) - DNS/identity must be first
2. pfSense (60s delay) - Network routing
3. NAS (60s delay) - Storage services
4. Production ESXi (60s delay) - Nested hypervisor
5. vCenter (100s delay) - Management layer
6. Veeam Inner (200s delay) - Backup services

**Production ESXi Auto-Startup Order:**
- Controlled by vApp startup order in vCenter
- Application VMs start automatically
- Dependencies managed through timing

See [01-VM-Startup-Shutdown.md](01-VM-Startup-Shutdown.md) for details.

================================================================================
DR FAILOVER WORKFLOW
================================================================================

**When to Activate DR ESXi:**
1. Production ESXi hardware failure
2. Critical ESXi error requiring rebuild
3. Planned maintenance requiring extended downtime

**Activation Process:**
1. Shutdown Production ESXi (if possible)
2. Power on DR ESXi
3. Add DR ESXi to vCenter cluster
4. Restore VMs from latest Veeam backup
5. Verify services operational
6. Update DNS/routing if needed

See [02-DR-Failover-Procedures.md](02-DR-Failover-Procedures.md) for step-by-step procedures.

================================================================================
RELATED DOCUMENTATION
================================================================================

### Platform Layer (Backup & Recovery)
- [Backup Strategy](../../02-Platform-Layer/Backup-DR/01-Backup-Strategy.md) - Veeam architecture
- [Emergency Shutdown](../../02-Platform-Layer/Backup-DR/02-Emergency-Shutdown.md) - Power-loss protection
- [Recovery Procedures](../../02-Platform-Layer/Backup-DR/03-Recovery-Procedures.md) - Restore workflows
- [Design Decisions](../../02-Platform-Layer/Backup-DR/04-Design-Decisions.md) - Architectural rationale
- [User Accounts](../../02-Platform-Layer/Identity/02-User-Accounts.md) - Authentication for DR

### Infrastructure Layer
- [Compute Resources](../Compute/) - Resource allocation
- [Network Architecture](../Network/) - Network design
- [Storage Architecture](../Storage/) - Storage configuration

================================================================================
QUICK REFERENCE
================================================================================

**IP Addresses:**
- Production ESXi: 10.0.20.101
- DR ESXi: 10.0.20.102
- ESXi Master: 10.0.20.100
- vCenter: 10.0.20.89

**Key Commands:**
```bash
# Check ESXi status
ping 10.0.20.101

# Power on DR ESXi (from ESXi Master host client)
# Navigate to DR ESXi VM and click "Power On"

# Verify vCenter connectivity
https://10.0.20.89
```

**RTO/RPO Targets:**
- RTO (Recovery Time): 15-20 minutes
- RPO (Recovery Point): 24 hours (daily backups)

================================================================================
END OF INFRASTRUCTURE DR GUIDE
================================================================================
