================================================================================
DR FAILOVER & TESTING PROCEDURES
Disaster Recovery Guide - Part 8
================================================================================
Last Updated: 2026-01-03
Back to: [README.md](README.md)

Cold standby DR failover, failback, and testing procedures.

================================================================================
TABLE OF CONTENTS
================================================================================
1. Cold Standby DR Failover Overview
2. DR Activation Procedure (Production → DR)
3. Failback Procedure (DR → Production)
4. Recovery from Power Loss Event
5. DR Testing Schedule & Procedures

================================================================================
1. COLD STANDBY DR FAILOVER OVERVIEW
================================================================================

## Strategy Summary

**Purpose**: Recover from ESXi Production (10.0.20.101) failures
**Method**: Manual activation of DR ESXi (10.0.20.102)
**Type**: Cold Standby (DR host powered OFF until needed)

**Performance Targets:**
- **RTO**: 15-20 minutes
- **RPO**: Live Migration or Last backup (Daily via Veeam)

## Why Cold Standby Instead of Active HA?

**Memory Ballooning Issue:**
- ESXi nested reserves 3GB on boot and doesn't release memory after VM migration
- Causes memory exhaustion on ESXi Master

**Trade-offs:**

✗ **Lost:**
- Automatic HA failover
- Live migration between hosts

✓ **Gained:**
- 30GB for Production (vs 22GB with active HA)
- Ability to run 3 K8s workers
- Application-layer HA compensates

**See:** [04-Design-Decisions.md](../../02-Platform-Layer/Backup-DR/04-Design-Decisions.md) for full rationale

## DR ESXi Host Specifications

| Component | Specification |
|-----------|---------------|
| **Hostname** | esxi-dr-01.home.lab |
| **IP Address** | 10.0.20.102 (Management) |
| **vMotion IP** | 10.0.30.102 |
| **Memory** | 27GB (allocated when active) |
| **vCPU** | 10 vCPU |
| **Storage** | 150GB thin provisioned |
| **Datastore** | DS_NVME_1 |
| **Current Status** | POWERED OFF |

================================================================================
2. DR ACTIVATION PROCEDURE (PRODUCTION → DR)
================================================================================

## Overview

**Total Time**: 15-20 minutes

| Step | Action | Time | Success Criteria |
|------|--------|------|------------------|
| 1 | Detect Production ESXi failure | 1 min | Alert triggered, production unreachable |
| 2 | Shutdown Production ESXi VM | 2 min | Production ESXi powered off, memory freed |
| 3 | Power on DR ESXi VM | 5 min | DR ESXi booted, connected to network |
| 4 | Connect DR ESXi to vCenter | 2 min | DR ESXi visible in vCenter cluster |
| 5 | Start critical VMs manually | 5-10 min | IPA, Vault, K8s Master running |
| 6 | Verify services | 3 min | All critical services responding |

---

## Step 1: Detect Production ESXi Failure

**Detection Methods:**
- Grafana monitoring alerts
- vCenter alarm: ESXi host not responding
- Manual observation: VMs unresponsive on 10.0.20.101

**Verification:**
```bash
# From Windows Host or ESXi Master
ping 10.0.20.101 -n 10
```

**Decision Point:**
- If Production ESXi recovers: Stand down
- If Production ESXi unresponsive for >5 minutes: Proceed to Step 2

---

## Step 2: Shutdown Production ESXi VM

**Purpose:** Free 27GB memory for DR ESXi

**Access vCenter:**
```
URL: https://vcenter.home.lab
User: administrator@vsphere.local
```

**Actions:**
1. Right-click ESXi Production VM
2. Power > Shut Down Guest OS (if responsive)
3. If unresponsive: Power > Power Off
4. Wait for VM to fully stop
5. Verify memory freed on ESXi Master

**Verification:**
```bash
# Check ESXi Master memory
ssh root@10.0.20.100
esxtop
# Press 'm' for memory view
# Verify ~27GB available
```

**Rollback:**
```bash
# If false alarm, power back on Production
# Right-click ESXi Production > Power > Power On
```

---

## Step 3: Power on DR ESXi VM

**vCenter Action:**
1. Navigate to ESXi DR VM in inventory
2. Right-click > Power > Power On
3. Open console to monitor boot
4. Wait for ESXi to fully boot (~5 minutes)

**Boot Sequence:**
```
1. BIOS/UEFI boot
2. ESXi kernel load
3. VMkernel network initialization
4. Management network comes online (10.0.20.102)
5. vMotion network comes online (10.0.30.102)
6. Datastore mounts (NAS_DS via NFS)
```

**Verification:**
```bash
# Test connectivity
ping 10.0.20.102 -n 10

# SSH to DR ESXi
ssh root@10.0.20.102

# Check datastore mounted
esxcli storage filesystem list | grep NAS_DS
```

**Success Criteria:**
- ✓ DR ESXi responds to ping
- ✓ SSH access available
- ✓ NAS_DS datastore mounted
- ✓ Management network online

---

## Step 4: Connect DR ESXi to vCenter

**Add to Cluster:**
1. vCenter > Hosts and Clusters
2. Right-click "home.lab Cluster"
3. Add Host
4. Hostname: 10.0.20.102 or esxi-dr-01.home.lab
5. Username: root
6. Accept SSL certificate
7. Assign license (if applicable)
8. Wait for host to appear in cluster

**Verify Cluster Status:**
- Host status: Connected
- Datastore: NAS_DS visible
- VMs: Visible but powered off
- Network: vMotion network connected

**Success Criteria:**
- ✓ DR ESXi shows "Connected" status
- ✓ All VMs from Production visible in inventory
- ✓ Shared datastores accessible

---

## Step 5: Start Critical VMs Manually

**VM Startup Order:**

**Phase 1 - Core Infrastructure (Start First):**
```
1. IPA (10.0.20.184)           - DNS, LDAP, Kerberos
   Wait: 2 minutes for full boot
   Verify: ping 10.0.20.184
           ssh veeam_emergency@10.0.20.184

2. Vault-01 (10.0.20.191)      - Secrets management leader
   Wait: 1 minute
   Verify: curl https://10.0.20.191:8200/v1/sys/health

3. Vault-02 (10.0.20.192)      - Secrets management node 2
4. Vault-03 (10.0.20.193)      - Secrets management node 3
   Wait: 1 minute for cluster formation
   Verify: All nodes joined cluster
```

**Phase 2 - Kubernetes Control Plane:**
```
5. K8s-Master (10.0.20.181)    - Kubernetes control plane
   Wait: 3 minutes for kubelet, API server
   Verify: ssh veeam_emergency@10.0.20.181
           kubectl get nodes
```

**Phase 3 - Kubernetes Workers (Parallel):**
```
6. K8s-Worker-1 (10.0.20.182)
7. K8s-Worker-2 (10.0.20.183)
8. K8s-Worker-3 (10.0.20.187)
   Wait: 2 minutes for nodes to join
   Verify: kubectl get nodes -o wide
           (All nodes show "Ready" status)
```

**Phase 4 - Support Services (Parallel):**
```
9.  Ansible (10.0.20.185)       - Automation
10. Jenkins (10.0.20.196)       - CI/CD
11. Monitor (10.0.20.186)       - Grafana + Prometheus
```

**Startup Commands (via vCenter):**
```bash
# For each VM:
# 1. Right-click VM > Power > Power On
# 2. Wait for VMware Tools to report "Running"
# 3. Verify network connectivity
```

**Verification Script:**
```bash
# Check all critical VMs
for ip in 10.0.20.184 10.0.20.191 10.0.20.192 10.0.20.193 \
          10.0.20.181 10.0.20.182 10.0.20.183 10.0.20.187 \
          10.0.20.185 10.0.20.186 10.0.20.196; do
    echo -n "Testing $ip: "
    ping -c 2 $ip > /dev/null 2>&1 && echo "OK" || echo "FAILED"
done
```

---

## Step 6: Verify Services

**Service Verification Checklist:**

**IPA (Identity Management):**
```bash
# DNS resolution
nslookup vcenter.home.lab 10.0.20.184

# LDAP service
ldapsearch -x -H ldap://10.0.20.184 -b "dc=home,dc=lab" -s base

# Kerberos
kinit admin@HOME.LAB
```

**Vault Cluster:**
```bash
# Health check all nodes
curl https://10.0.20.191:8200/v1/sys/health
curl https://10.0.20.192:8200/v1/sys/health
curl https://10.0.20.193:8200/v1/sys/health

# Verify unsealed status (should be unsealed if auto-unseal configured)
```

**Kubernetes Cluster:**
```bash
# Check node status
kubectl get nodes

# Expected output:
# NAME          STATUS   ROLES           AGE   VERSION
# k8s-master    Ready    control-plane   Xd    v1.x.x
# k8s-worker1   Ready    <none>          Xd    v1.x.x
# k8s-worker2   Ready    <none>          Xd    v1.x.x
# k8s-worker3   Ready    <none>          Xd    v1.x.x

# Check system pods
kubectl get pods -n kube-system

# Check application workloads
kubectl get pods --all-namespaces
```

**Monitoring:**
```bash
# Access Grafana
URL: http://10.0.20.186:3000
User: admin

# Verify dashboards showing data
# Check Prometheus targets: http://10.0.20.186:9090/targets
```

**Jenkins:**
```bash
# Access Jenkins
URL: http://10.0.20.196:8080
User: admin

# Verify Jenkins online and responsive
```

**Success Criteria:**
- ✓ All VMs pingable
- ✓ All services responding on expected ports
- ✓ Kubernetes cluster fully operational
- ✓ Monitoring dashboards showing data
- ✓ No critical errors in logs

================================================================================
3. FAILBACK PROCEDURE (DR → PRODUCTION)
================================================================================

## Scenario

DR activated, Production ESXi fixed, ready to failback

## Procedure

### Step 1: Verify Production ESXi Ready

```bash
# Boot Production ESXi
# Verify network, datastores, cluster connection
ping 10.0.20.101
ssh root@10.0.20.101
```

**Checks:**
- Network connectivity: ✓
- Datastores mounted: ✓
- vCenter connection: ✓
- Memory available: ✓

---

### Step 2: Graceful Shutdown VMs on DR

```bash
# vCenter > Select all VMs on DR ESXi
# Right-click > Guest Shutdown
# Wait for all VMs to stop
```

**Wait Time:** 5-10 minutes for graceful shutdown

---

### Step 3: vMotion VMs to Production (if shared storage)

```bash
# For each VM:
# Right-click > Migrate
# Change compute resource only
# Destination: ESXi Production
```

**Alternative:** Cold migration (if not using vMotion)

---

### Step 4: Power On VMs on Production

```bash
# Power off VMs on DR (if still running)
# Power on VMs on Production ESXi
# Verify auto-startup sequence executes
```

**See:** [01-VM-Startup-Shutdown.md](01-VM-Startup-Shutdown.md) for startup order

---

### Step 5: Disconnect DR ESXi

```bash
# vCenter > ESXi DR > Enter Maintenance Mode
# Right-click > Disconnect
# Right-click > Remove from Inventory (optional)
```

---

### Step 6: Power off DR ESXi VM

```bash
# vCenter > ESXi DR VM > Power Off
```

---

### Step 7: Verify Production Restored

```bash
# All services operational
# Monitoring shows healthy status
```

**Post-Failback Checklist:**
- [ ] All VMs running on Production ESXi
- [ ] All services functional
- [ ] DR ESXi powered off
- [ ] vCenter shows Production ESXi connected
- [ ] Monitoring dashboards healthy

================================================================================
4. RECOVERY FROM POWER LOSS EVENT
================================================================================

## Scenario

Emergency shutdown executed, power restored, need to restart infrastructure

**See:** [02-Emergency-Shutdown.md](../../02-Platform-Layer/Backup-DR/02-Emergency-Shutdown.md) for shutdown details

## Recovery Procedure

### Step 1: Power on Laptop

- Connect AC power
- Boot Windows
- Verify battery charged

---

### Step 2: Start VMware Workstation

- Open VMware Workstation
- Auto-resume may prompt for ESXi Master

---

### Step 3: Power on ESXi Master VM

```bash
# Workstation > ESXi Master > Power On
# Wait 5 minutes for boot
# Verify ping 10.0.20.100
```

**Boot Verification:**
```bash
ping 10.0.20.100 -t
# Wait for response
ssh root@10.0.20.100
```

---

### Step 4: ESXi Master Auto-Startup

**Automatic VM startup sequence executes:**

See [01-VM-Startup-Shutdown.md](01-VM-Startup-Shutdown.md) for complete order

**Expected Sequence:**
1. IPA (60s delay)
2. pfSense (60s after IPA)
3. NAS (60s after pfSense)
4. Production ESXi (60s after NAS)
5. vCenter (100s after Production ESXi)
6. Veeam (200s after vCenter)

**Total Boot Time:** ~8 minutes

---

### Step 5: Verify Infrastructure

```bash
# Check all VMs running
# vCenter > Hosts and Clusters
# Verify all VMs show "Powered On"
```

**Quick Check:**
```powershell
# From Windows Host
ping 10.0.20.89   # vCenter
ping 10.0.20.100  # ESXi Master
ping 10.0.20.101  # Production ESXi
ping 10.0.20.195  # Inner Veeam
```

---

### Step 6: Verify Services

**IPA:**
```bash
# DNS resolution
nslookup vcenter.home.lab 10.0.20.89

# IPA web UI
https://10.0.20.89
```

**Vault:**
```bash
# Health check
curl https://10.0.20.191:8200/v1/sys/health
```

**K8s:**
```bash
kubectl get nodes
kubectl get pods --all-namespaces
```

**Monitoring:**
```bash
# Access Grafana
http://10.0.20.186:3000
```

---

### Step 7: Review Shutdown Log

```powershell
Get-Content "C:\Scripts\ShutdownLog.txt" -Tail 100
```

**Look for:**
- All phases completed?
- Any errors during shutdown?
- Veeam jobs killed successfully?
- ESXi hosts shutdown gracefully?

---

### Step 8: Check for Issues

**Common Issues After Power Loss:**

**VM Corruption:**
```bash
# Check VM logs for errors
# vCenter > VM > Monitor > Logs
```

**Backup Job Failures:**
```powershell
# Open Veeam console
# Check for interrupted jobs
# Retry failed backups if needed
```

**Network Connectivity:**
```bash
# Verify all VMs can reach each other
# Check pfSense routing
```

**Services Failed to Start:**
```bash
# SSH to affected VM
systemctl status <service>
journalctl -xe
```

**Success Criteria:**
- ✓ All VMs booted successfully
- ✓ All services operational
- ✓ No data corruption detected
- ✓ Backups can resume normally

================================================================================
5. DR TESTING SCHEDULE & PROCEDURES
================================================================================

## Test Types and Frequency

| Test Type | Frequency | Duration | Impact | Last Performed |
|-----------|-----------|----------|--------|----------------|
| **DR Activation Test** | Monthly | 1-2 hours | No production impact | TBD |
| **Failover Test** | Quarterly | 2-3 hours | Planned maintenance window | TBD |
| **Backup Restore Test** | Monthly | 2 hours | Test environment only | TBD |
| **Documentation Review** | Quarterly | 1 hour | No impact | 2026-01-03 |
| **Emergency Shutdown Drill** | Quarterly | 30 minutes | Controlled shutdown | TBD |

---

## Monthly DR Activation Test

**Purpose**: Verify DR ESXi can boot and accept VMs

**Procedure**:
1. Schedule maintenance window (non-production hours)
2. Power on DR ESXi VM
3. Verify network connectivity (management + vMotion)
4. Connect to vCenter cluster
5. Power on 1 test VM
6. Verify VM boots and network accessible
7. Shutdown test VM
8. Disconnect DR ESXi from vCenter
9. Power off DR ESXi VM
10. Document results

**Success Criteria**:
- ✓ DR ESXi boots successfully
- ✓ Datastores mount correctly
- ✓ Test VM runs without issues
- ✓ Network connectivity verified

---

## Quarterly Failover Test

**Purpose**: Full DR scenario simulation

**Procedure**:
1. Schedule 3-hour maintenance window
2. Notify all stakeholders
3. Take snapshots of critical VMs (optional safety net)
4. Follow full DR Activation Procedure (Steps 1-6)
5. Run applications for 30 minutes on DR
6. Verify all services functional
7. Failback to Production ESXi
8. Verify Production restored
9. Delete snapshots (if taken)
10. Document lessons learned

**Success Criteria**:
- ✓ RTO achieved (15-20 minutes)
- ✓ All critical services operational on DR
- ✓ Failback successful
- ✓ No data loss

---

## Monthly Backup Restore Test

**Purpose**: Verify backup integrity and restore capability

**See:** [03-Recovery-Procedures.md](../../02-Platform-Layer/Backup-DR/03-Recovery-Procedures.md) for restore details

**Procedure**:
1. Select 1 critical VM for restore test
2. Create test restore destination (isolated network)
3. Restore VM from latest Veeam backup
4. Power on restored VM
5. Verify VM boots and OS functional
6. Check application functionality
7. Delete test restored VM
8. Document results

**Rotation Schedule**:
- Month 1: IPA
- Month 2: Vault-01
- Month 3: K8s-Master
- (Repeat)

---

## Quarterly Emergency Shutdown Drill

**Purpose**: Validate automated power-loss protection

**See:** [02-Emergency-Shutdown.md](../../02-Platform-Layer/Backup-DR/02-Emergency-Shutdown.md) for script details

**Procedure**:
1. Verify no production workloads running
2. Modify BatteryMonitor.ps1 trigger to 90%
3. Disconnect AC power
4. Monitor shutdown sequence
5. **CRITICAL**: Cancel laptop shutdown before completion
   ```powershell
   shutdown /a
   ```
6. Restore BatteryMonitor.ps1 trigger to 75%
7. Reconnect AC power
8. Review shutdown log
9. Document results

**Success Criteria**:
- ✓ All phases execute in order
- ✓ Veeam jobs stopped
- ✓ ESXi hosts shutdown gracefully
- ✓ Total time < 13 minutes

---

## Documentation Review (Quarterly)

**Procedure**:
1. Review all DR documentation files
2. Verify IP addresses current
3. Update file paths if changed
4. Test all command examples
5. Update "Last Updated" dates
6. Document any changes

**Files to Review:**
- [README.md](README.md)
- [01-VM-Startup-Shutdown.md](01-VM-Startup-Shutdown.md)
- [02-DR-Failover-Procedures.md](02-DR-Failover-Procedures.md)
- Platform Layer Backup-DR documentation

================================================================================
RELATED DOCUMENTATION
================================================================================

- [README.md](README.md) - Main overview and navigation
- [01-VM-Startup-Shutdown.md](01-VM-Startup-Shutdown.md) - Auto-startup sequences
- [02-Emergency-Shutdown.md](../../02-Platform-Layer/Backup-DR/02-Emergency-Shutdown.md) - Emergency shutdown details
- [03-Recovery-Procedures.md](../../02-Platform-Layer/Backup-DR/03-Recovery-Procedures.md) - Veeam restore procedures
- [04-Design-Decisions.md](../../02-Platform-Layer/Backup-DR/04-Design-Decisions.md) - Why cold standby?
- [05-Configuration-Reference.md](../../02-Platform-Layer/Backup-DR/05-Configuration-Reference.md) - IP addresses, settings

Back to: [README.md](README.md)

================================================================================
END OF DR FAILOVER & TESTING PROCEDURES
================================================================================
