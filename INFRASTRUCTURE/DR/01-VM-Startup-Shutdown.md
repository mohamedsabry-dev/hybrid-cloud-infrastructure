================================================================================
VM STARTUP/SHUTDOWN SEQUENCES
Disaster Recovery Guide - Part 4
================================================================================
Last Updated: 2026-01-03
Back to: [README.md](README.md)

================================================================================
TABLE OF CONTENTS
================================================================================
1. ESXi Auto-Startup Overview
2. Nested ESXi (Production - 10.0.20.101)
3. ESXi Master (10.0.20.100)
4. DR Script Integration
5. Configuration & Testing

================================================================================
1. ESXI AUTO-STARTUP OVERVIEW
================================================================================

VMware ESXi supports automatic VM startup/shutdown ordering during host
boot/shutdown events. This ensures proper dependency management.

## Why This Matters

**During Shutdown:**
- VMs shutdown in reverse dependency order
- Infrastructure components (storage, network, auth) remain online longest
- Application VMs shutdown first (dependent on infrastructure)

**During Startup:**
- Core services start first (DNS, auth)
- Network and storage next
- Nested hypervisors after infrastructure is ready
- Management tools last (not critical for initial boot)

## Configuration Location

**For Each ESXi Host:**
1. Connect to vCenter
2. Navigate to Host
3. Configure > Virtual Machine Startup/Shutdown
4. Enable automatic startup
5. Configure order and delays

================================================================================
2. NESTED ESXI (PRODUCTION - 10.0.20.101)
================================================================================

## VM Startup/Shutdown Table

| Order | VM Name       | Startup Delay | Shutdown Behavior | Shutdown Delay |
|-------|---------------|---------------|-------------------|----------------|
| 1     | Ansible       | 60s           | Guest shutdown    | 60s            |
| 2     | Vault-01      | 60s           | Guest shutdown    | 60s            |
| 3     | Vault-02      | 0s            | Guest shutdown    | 0s             |
| 4     | Vault-03      | 0s            | Guest shutdown    | 0s             |
| 5     | Monitor       | 60s           | Guest shutdown    | 60s            |
| 6     | Jenkins       | 60s           | Guest shutdown    | 60s            |
| 7     | K8s-Master    | 60s           | Guest shutdown    | 60s            |
| 8     | K8s-Worker-1  | 60s           | Guest shutdown    | 60s            |
| 9     | K8s-Worker-2  | 0s            | Guest shutdown    | 0s             |
| 10    | K8s-Worker-3  | 0s            | Guest shutdown    | 0s             |

## Startup Logic

**Layer 1: Core Services**
- Ansible (automation platform)
- Vault cluster (Vault-01, Vault-02, Vault-03)
- Monitor (monitoring stack)

**Layer 2: CI/CD**
- Jenkins (depends on Vault for secrets)

**Layer 3: Container Orchestration**
- K8s Master (must start before workers)
- K8s Workers (depend on master)

**Delay Rationale:**
- 60s delays ensure previous tier is fully online
- 0s delays for cluster members (Vault-02/03, K8s-Worker-2/3) start simultaneously with first member

## Shutdown Logic

**Reverse Order (Applications → Infrastructure)**

1. **K8s Workers shutdown first** (60s delay after master)
   - Workloads drain from workers
   - Master remains online for cluster coordination

2. **K8s Master next** (60s after workers)
   - Cluster control plane shuts down cleanly

3. **Jenkins** (60s)
   - CI/CD pipelines complete or abort

4. **Monitor** (60s)
   - Monitoring/alerting systems shutdown

5. **Vault Cluster** (60s)
   - Secret management shutdown (reverse HA order)

6. **Ansible last** (60s)
   - Automation platform (least critical)

**Guest Shutdown = Graceful OS Shutdown via VMware Tools**

## Total Timing

**Startup:** ~8 minutes (cumulative delays for 10 VMs)
**Shutdown:** ~5 minutes (parallel + sequential delays)

================================================================================
3. ESXI MASTER (10.0.20.100)
================================================================================

## VM Startup/Shutdown Table

| Order | VM Name               | Startup Delay | Shutdown Behavior | Shutdown Delay |
|-------|-----------------------|---------------|-------------------|----------------|
| 1     | IPA                   | 60s           | Guest shutdown    | 60s            |
| 2     | pfSense FW            | 60s           | Guest shutdown    | 60s            |
| 3     | NAS Storage           | 60s           | Guest shutdown    | 60s            |
| 4     | Production Server     | 60s           | Guest shutdown    | 60s            |
| 5     | VMware vCenter Server | 100s          | Guest shutdown    | 60s            |
| 6     | Veeam                 | 200s          | Guest shutdown    | 20s            |

**Note:** "Production Server" = Production ESXi (nested) at 10.0.20.101

## Startup Logic

**Tier 1: DNS & Authentication (Critical Foundation)**
1. **IPA** (60s delay)
   - FreeIPA domain controller
   - DNS server for 10.0.20.x network
   - MUST be first (everything depends on DNS)

**Tier 2: Network Gateway**
2. **pfSense** (60s after IPA)
   - NAT gateway between 192.168.0.x and 10.0.20.x
   - Firewall rules
   - Depends on IPA for DNS resolution

**Tier 3: Storage**
3. **NAS** (60s after pfSense)
   - Shared storage for backups
   - NFS/SMB services
   - Depends on network being online

**Tier 4: Nested Hypervisor**
4. **Production ESXi** (60s after NAS)
   - Nested hypervisor hosting 10 VMs
   - Triggers its own auto-startup sequence (see Section 2 above)
   - Depends on DNS, network, storage

**Tier 5: Management Layer**
5. **vCenter** (100s after Production ESXi)
   - Longer delay: Wait for Production ESXi to stabilize
   - Management of all ESXi hosts
   - Not critical for initial boot, but needed for management

**Tier 6: Backup Server**
6. **Veeam** (200s after vCenter)
   - Longest delay: Lowest priority for boot
   - Backup operations (not critical for startup)
   - Depends on vCenter API being available

## Shutdown Logic (Reverse Dependency Order)

**During Emergency Shutdown (triggered by EmergencyLabShutdown.ps1):**

```
ESXi Master Shutdown Signal
    ↓
Reverse Auto-Shutdown Sequence
    ↓
    ├─ Veeam shutdown first (20s delay)
    ├─ vCenter shutdown (60s delay)
    ├─ Production ESXi shutdown (60s delay)
    │     ↓
    │     └─ Triggers Nested Auto-Shutdown (10 VMs)
    ├─ NAS shutdown (60s delay)
    ├─ pfSense shutdown (60s delay)
    └─ IPA shutdown last (60s delay)
```

**Why This Order?**

1. **Veeam first** (shortest delay: 20s)
   - Non-critical for infrastructure
   - Can die quickly without affecting other services

2. **vCenter before ESXi**
   - Management layer before compute layer
   - Prevents vCenter from trying to manage shutting-down hosts

3. **Production ESXi** (60s)
   - Triggers nested auto-shutdown of 10 VMs inside it
   - Most complex shutdown (waits for inner VMs)

4. **NAS, pfSense, IPA last**
   - Infrastructure services needed until the end
   - DNS (IPA) needed for all communications
   - Network (pfSense) needed for connectivity
   - Storage (NAS) needed for any final writes

## Shutdown Delay Meaning

**Important:** Shutdown delay is AFTER sending shutdown signal

- Delay = time ESXi waits after sending guest shutdown signal
- NOT a delay before starting shutdown
- Purpose: Ensure VM has time to shut down gracefully before ESXi moves to next VM

================================================================================
4. DR SCRIPT INTEGRATION
================================================================================

## How Emergency Shutdown Triggers Auto-Shutdown

When `EmergencyLabShutdown.ps1` runs:

### Phase 3: Nested ESXi Shutdown

```powershell
Stop-VMHost -VMHost 10.0.20.101 -Force -Confirm:$false
```

**What Happens:**
1. vCenter sends shutdown signal to Production ESXi
2. Production ESXi auto-shutdown sequence begins
3. 10 VMs shutdown in configured order (Section 2 table)
4. Script waits 3 minutes for completion

### Phase 4: Master ESXi Shutdown

```powershell
Stop-VMHost -VMHost 10.0.20.100 -Force -Confirm:$false
```

**What Happens:**
1. vCenter sends shutdown signal to Master ESXi
2. Master ESXi auto-shutdown sequence begins
3. 6 VMs shutdown in configured order (Section 3 table)
4. Production ESXi (nested) triggers its own sequence again (if still running)
5. Script waits 3 minutes for completion

## Dependency Chain Example

**Complete Shutdown Flow:**

```
Laptop Battery → BatteryMonitor.ps1 → EmergencyLabShutdown.ps1
    ↓
Phase 3: Shutdown Nested ESXi
    ↓
Production ESXi (10.0.20.101) receives shutdown signal
    ↓
    ├─ Ansible shutdown
    ├─ Vault-01, Vault-02, Vault-03 shutdown
    ├─ Monitor shutdown
    ├─ Jenkins shutdown
    ├─ K8s-Master shutdown
    └─ K8s-Worker-1, K8s-Worker-2, K8s-Worker-3 shutdown
    ↓
Phase 4: Shutdown Master ESXi
    ↓
Master ESXi (10.0.20.100) receives shutdown signal
    ↓
    ├─ Veeam shutdown (20s delay)
    ├─ vCenter shutdown (60s delay)
    ├─ Production ESXi shutdown (60s delay) [if still running from Phase 3]
    ├─ NAS shutdown (60s delay)
    ├─ pfSense shutdown (60s delay)
    └─ IPA shutdown (60s delay)
```

================================================================================
5. CONFIGURATION & TESTING
================================================================================

## How to Configure Auto-Startup

**For Each ESXi Host:**

1. **Connect to vCenter**
   - Open vSphere Client
   - Connect to vCenter (10.0.20.89)

2. **Navigate to Host**
   - Select ESXi host from inventory
   - Click "Configure" tab

3. **Enable Auto-Startup**
   - System > Virtual Machine Startup/Shutdown
   - Click "Edit"
   - Enable "Start and stop virtual machines with the system"

4. **Configure VM Order**
   - Drag VMs to desired order
   - Set startup delays (seconds)
   - Set shutdown behavior: "Guest Shutdown" (requires VMware Tools)
   - Set shutdown delays (seconds)

5. **Save Configuration**

## Critical Requirements

**VMware Tools MUST Be Installed on ALL VMs**

Without VMware Tools:
- "Guest shutdown" fails
- ESXi performs hard power-off after timeout
- Risk of data corruption

**Verify VMware Tools:**
```
# In vCenter, check VM summary
Tools Status: Running (Current)
```

## Testing Auto-Shutdown

**Manual Test (Non-Emergency):**

1. **Trigger Shutdown via vCenter**
   ```
   Right-click ESXi host > Power > Shut Down
   ```

2. **Monitor VM Shutdown Order**
   - Watch VMs in vCenter
   - Verify they shutdown in configured order
   - Check delays are respected

3. **Review Logs**
   - ESXi: /var/log/hostd.log
   - VM: /var/log/vmware-vmsvc.log
   - Look for guest shutdown signals

4. **Restart and Verify**
   - Power on ESXi host
   - Verify VMs auto-start in configured order
   - Check delays are correct

## Troubleshooting

**VMs Don't Shutdown Gracefully**

**Symptoms:**
- VMs are hard powered off instead of guest shutdown
- ESXi doesn't wait for VM shutdown

**Checks:**
1. VMware Tools installed and running?
2. VMware Tools up to date?
3. Shutdown delay long enough for OS shutdown?

**Solution:**
```bash
# On VM, verify VMware Tools
systemctl status vmware-tools  # Linux
```

**VMs Don't Auto-Start**

**Symptoms:**
- ESXi boots but VMs remain powered off

**Checks:**
1. Auto-startup enabled on ESXi host?
2. VMs in auto-startup list?
3. VMware Workstation snapshot delay interfering?

**Solution:**
- Verify configuration in vCenter
- Manually start VMs to test
- Check ESXi logs for errors

**Shutdown Takes Too Long**

**Symptoms:**
- Phase 3/4 timeout (3 minutes not enough)

**Checks:**
1. Are VMs actually shutting down?
2. Any VMs hanging during shutdown?
3. Network connectivity issues preventing guest shutdown?

**Solution:**
- Increase shutdown delays in ESXi config
- Increase wait time in EmergencyLabShutdown.ps1
- Investigate hung VMs

================================================================================
RELATED DOCUMENTATION
================================================================================

- [02-Emergency-Shutdown.md](../../02-Platform-Layer/Backup-DR/02-Emergency-Shutdown.md) - How DR script triggers these sequences
- [04-Design-Decisions.md](../../02-Platform-Layer/Backup-DR/04-Design-Decisions.md) - Why this ordering? Why these delays?
- [05-Configuration-Reference.md](../../02-Platform-Layer/Backup-DR/05-Configuration-Reference.md) - Quick reference for startup order

Back to: [README.md](README.md)
