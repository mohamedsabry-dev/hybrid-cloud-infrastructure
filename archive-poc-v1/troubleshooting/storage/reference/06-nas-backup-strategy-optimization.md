# NAS Backup Strategy Optimization

> **Troubleshooting case: Optimizing Veeam backup approach to prevent NAS VM resource exhaustion**

---

## Problem Statement

### Initial Incident
Previously, when running 3 simultaneous Veeam backup snapshots, the environment experienced:
- **NAS VM**: High CPU/memory utilization (resource exhaustion)
- **Impact**: Multiple VMs stunned and required reboot
- **Critical Issue**: Some VMs experienced kernel panics

### Root Cause Analysis
- NAS VM had insufficient memory for concurrent backup operations
- Multiple simultaneous backup tasks saturated disk I/O (270% utilization spikes)
- CPU became bottleneck during heavy storage operations
- Network latency spikes during backup operations (700ms+ pings)

### Immediate Mitigation
- Increased NAS VM memory from 8GB → 9GB
- Reduced risk of memory starvation during backups

---

## Objective

Design an optimal backup strategy that:
1. **Prevents resource exhaustion** on NAS VM
2. **Minimizes impact** on running production VMs
3. **Maintains reasonable backup windows** (acceptable time to complete)
4. **Supports automated backup scheduling** with proper cooldown periods
5. **Accommodates dual Veeam architecture** (internal + external Windows host)

---

## Testing Methodology

### Monitoring Commands

#### NAS VM Performance Monitoring

**A. Storage Throughput & Wait Time:**
```bash
# Install sysstat if needed
sudo apt install sysstat

# Monitor every 2 seconds (disk stats, extended, kilobytes)
iostat -dxk 2
```
**Key Metrics:**
- `%util` - Disk saturation (100% = fully saturated)
- `await` - Average I/O wait time in ms (spikes indicate lag)

**B. Identify Heavy I/O Processes:**
```bash
# Install iotop if needed
sudo apt install iotop

# Show only active processes
sudo iotop -o
```
**Key Metrics:**
- `DISK READ` column - Identify Veeam transport process (500+ MB/s)

**C. Combined System Health:**
```bash
# Install dstat if needed
sudo apt install dstat

# Combined CPU, Disk, Network, Memory
dstat -cdngy
```
**Key Metrics:**
- `dsk/total` - Total disk I/O
- `net/total` - Network throughput
- Gap between disk read and network send (shows compression effectiveness)

#### Production VM Impact Testing

**Network Latency Test (From Vault or K8s nodes):**
```bash
# Continuous ping to NAS VM
ping [NAS_IP] -i 0.2
```
**What to look for:**
- Sudden jumps in `time=X.XX ms`
- Packet loss (indicates CPU stun)
- Jitter caused by heavy I/O interrupts

**Storage Responsiveness Test:**
```bash
# Install ioping if needed
sudo apt install ioping

# Test I/O latency to shared folder
ioping -c 20 /path/to/shared/folder
```
**What to look for:**
- Response time consistency
- Evidence of I/O stun during backup operations

---

## Test Results: Comprehensive Comparison

### Four Backup Transport Modes Tested

| Metric | Test 1: Network (NBD) | Test 2: Direct Storage (DSA) | Test 3: HotAdd (Appliance) | Test 4: Optimized NBD |
|--------|----------------------|------------------------------|----------------------------|----------------------|
| **Configuration** | 2 Tasks / 125MB Rule | Native NFS/SAN | SCSI Hot-Plug | 1 Task / 250MB Rule |
| **Backup Time** | ~12 Minutes | ~4 Minutes ⚡ | ~6 Minutes | ~10 Minutes |
| **Processing Rate** | 243 MB/s | 217 MB/s | ~200 MB/s | 220 MB/s (Stable)  |
| **Max CPU Freq** | 3,700 MHz | 5,300 MHz | 6,300 MHz  | 3,300 MHz  |
| **Disk Utilization** | 135% - 270%  | 130% - 170% | 170% | 25% Avg / 88% Peak  |
| **Max Ping Latency** | 782 ms | 900 ms  | 137 ms  | 701 ms |
| **Packet Loss** | 0  | 0  | 2 Packets  | 1 (Congestion)  |
| **Snapshot Removal** | Variable | Fast | 1.5 Min  | 5 Seconds  |

**Legend:**
- = Best/Acceptable performance
-  = Warning/Concern
- ⚡ = Fastest
- = Problematic

---

## Analysis & Key Learnings

### 1. Speed vs. Stability Trade-off

**Direct Storage Access (DSA)** - Test 2:
- **Fastest**: 4 minutes backup time
- **Efficient**: Best raw data movement
- **High CPU**: 5,300 MHz peak (nested hypervisor stress)
- **High Disk I/O**: 130-170% utilization
- **Verdict**: Speed comes at the cost of system stress in nested environments

### 2. The Danger of HotAdd Mode

**HotAdd (Appliance)** - Test 3:
-  **Highest CPU**: 6,300 MHz peak (extreme stress)
- **Packet Loss**: 2 packets dropped during operation
- **Slowest Snapshot Removal**: 1.5 minutes (hardware stun)
- **Verdict**: **NOT SUITABLE** for production services (Kubernetes, Vault) in nested labs

### 3. Concurrency is the Multiplier

**Network Mode (NBD) with 2 Tasks** - Test 1:
- **Disk Saturation**: 135-270% utilization spikes
-  **Variable Performance**: Unpredictable during concurrent operations

**Optimized Network Mode (NBD) with 1 Task** - Test 4:
- **Stable Disk I/O**: 25% average, 88% peak (controlled)
- **Fastest Snapshot Removal**: 5 seconds
- **Predictable Performance**: Most consistent results
- **Verdict**: **Concurrency limiting is more effective than bandwidth throttling**

### 4. Nested Networking Reality

**High Ping Latency (700ms+) in NBD Mode:**
- **Root Cause**: CPU-based virtual switching in nested ESXi
- **Explanation**: Guest ESXi must process every packet via software
- **Impact**: 1Gb link saturates CPU cycles for networking
- **Verdict**: Expected behavior in nested environments, not a defect

---

## Final Test: Validation Run (Direct Storage with 1 Task)

After selecting the Direct Storage Access (DSA) approach with 1 concurrent task, we conducted a final validation test:

### Test Configuration
- **Transport Mode**: Direct Storage Access (NFS/SAN)
- **Concurrent Tasks**: 1 (reduced from 2)
- **VM Target**: Same test VM used in all previous tests
- **Duration**: 4 minutes

### Results

| Metric | Value | Assessment |
|--------|-------|------------|
| **Average Ping** | 1.8 ms |  Excellent (baseline) |
| **Max Ping** | 505 ms |  Acceptable (spike during peak I/O) |
| **Packet Loss** | 0 |  Perfect |
| **Backup Duration** | 4 minutes |  Fast |
| **Snapshot Removal** | 2 seconds |  Excellent |
| **Average Disk Utilization** | 45% |  Healthy |
| **Disk Utilization Spikes** | 400% (1×), 350% (1×), 80% (1×) |  Acceptable (brief spikes) |
| **NAS VM CPU** | 5,500 MHz peak |  High but acceptable |

### Validation Conclusion
- **NAS VM**: Has sufficient resources and remains stable
- **No Packet Loss**: Production VMs unaffected
- **Fast Operations**: 4 minutes backup + 2 seconds snapshot removal
-  **CPU Spikes**: Brief but acceptable given 9GB memory and 4vCPU 12GHZ on normal
- **Verdict**: **APPROVED** - This approach is safe for production use

---

## Recommended Backup Strategy

### Selected Approach: Direct Storage Access (DSA) with 1 Concurrent Task

**Why This Approach?**
1. **Fast**: 4-minute backup time (acceptable)
2. **Safe**: No packet loss, predictable resource usage
3. **Stable**: NAS VM has sufficient CPU/memory to handle operations
4. **Tested**: Validated through multiple iterations
5. **Production-Ready**: Won't stun critical services (Vault, K8s)

### Backup Architecture Considerations

#### Dual Veeam Architecture
**Why Two Veeam Servers?**
- **Veeam Free Edition Limit**: 10 VMs maximum per instance
- **Our Environment**: 11 internal VMs + 5 infrastructure VMs = 16 total

**Solution:**
- **Internal Veeam** (on NAS VM): Backs up 10 internal production VMs
- **External Veeam** (Windows Host): Backs up 5 infrastructure VMs + 1 remaining VM
- **Future**: Backup copy jobs between Veeam servers for redundancy

### Backup Scheduling Strategy

#### Scheduling Constraints & Design

**Active Environment Window:**
- Laptop operational: 8:00 PM - 10:00 PM (2 hours)
- Backup window: Within active hours

**Cooldown Requirement:**
- **Why Needed?** DR script monitors laptop battery
- **DR Script Logic:**
  1. Check if backup is in progress
  2. Wait up to 10 minutes for backup to complete
  3. Then trigger graceful shutdown
- **Problem**: If backups are chained (no gap), script may wait indefinitely
- **Solution**: 5-minute gaps between backup tasks

**Retry Settings:**
- **Retry Attempts**: 1 time only
- **Wait Time Between Retries**: 5 minutes
- **Rationale**: We don't want backup tasks to overlap in runtime. If a backup fails, it gets one retry after 5 minutes, then stops to avoid collisions with the next scheduled task.

#### Implemented Backup Schedule

**Internal Veeam Server (10 Production VMs):**

Based on testing and resource constraints, we implemented a staggered schedule with 15-minute intervals to ensure proper cooldown between tasks:

| VM Name | Next Run Time | Interval | Notes |
|---------|---------------|----------|-------|
| **K8s Worker-1** | 9:30 PM | Daily | First in sequence |
| **K8s Worker-2** | 9:45 PM | Daily | +15 min gap |
| **K8s Worker-3** | 10:00 PM | Daily | +15 min gap |
| **Jenkins** | 10:15 PM | Daily | +15 min gap |
| **Ansible** | 8:00 PM (next day) | Daily | New cycle start |
| **Vault-01** | 8:15 PM | Daily | +15 min gap |
| **Vault-02** | 8:30 PM | Daily | +15 min gap |
| **Vault-03** | 8:45 PM | Daily | +15 min gap |
| **IPA** | 9:00 PM | Daily | +15 min gap |
| **K8s Master** | 9:15 PM | Daily | +15 min gap |

**Schedule Characteristics:**
- **Total Duration**: ~2.5 hours (8:00 PM - 10:30 PM)
- **Interval**: 15 minutes between tasks
- **Expected Backup Time**: 4-6 minutes per VM
- **Cooldown**: ~9-11 minutes between backups
- **Retry Policy**: 1 retry with 5-minute wait
- **Transport Mode**: Direct Storage Access (DSA)
- **Concurrent Tasks**: 1 maximum

**Why 15-Minute Intervals?**
1. **Backup Duration**: ~4-6 minutes per VM
2. **Cooldown Period**: ~9-11 minutes for NAS VM recovery
3. **Retry Buffer**: If retry needed (5 min wait + 4 min backup), completes before next task
4. **DR Script Safety**: Ensures no overlapping backups for battery monitoring logic

### NAS VM Snapshot Consideration

**Critical Factor:** NAS VM itself needs backup
- **NAS VM Snapshot Size**: Could reach 400GB (thick provisioned disks)
- **Snapshot Creation/Deletion Time**: Significant (needs testing)
- **Risk**: High I/O during NAS snapshot could stun environment

**Testing Plan:**
1. **Test 1: Isolated NAS Snapshot**
   - Shutdown entire internal environment
   - Take NAS VM snapshot
   - Measure: Time, CPU, disk utilization

2. **Test 2: Concurrent Operations**
   - Run internal environment + NAS backup simultaneously
   - Measure impact on production VMs
   - **Prerequisite**: All other backups completed + snapshots taken (rollback safety)

3. **Schedule Maintenance Window**
   - Plan for potential service disruption
   - Have rollback plan ready

---

## Monitoring & Validation Checklist

### Pre-Backup Checks
- [ ] Verify NAS VM memory: 9GB allocated
- [ ] Confirm Veeam transport mode: Direct Storage Access (DSA)
- [ ] Ensure concurrent tasks: 1 maximum
- [ ] Check available datastore space for snapshots

### During Backup Monitoring
```bash
# Run these commands in separate terminals on NAS VM

sudo dnf install sysstat iotop dstat

# Terminal 1: Disk I/O
# To install ## 
iostat -dxk 2

# Terminal 2: Process monitoring
sudo iotop -o

# Terminal 3: Combined stats
dstat -cdngy
```

### From Production VMs (Vault/K8s)
```bash
# Monitor network impact
ping [NAS_IP] -i 0.2 | tee backup-ping-test.log

# Check storage responsiveness
ioping -c 20 /mnt/shared_storage
```

### Post-Backup Validation
- [ ] Check for packet loss in ping logs
- [ ] Verify all VMs remained responsive
- [ ] Confirm backup completed successfully in Veeam
- [ ] Validate snapshot removal time (<5 seconds)
- [ ] Review NAS VM resource utilization logs

---

## Future Considerations

### 1. NAS VM Snapshot Strategy
- Test NAS VM backup during off-hours (if possible)
- Consider external backup for NAS VM (Windows Veeam instance)
- Evaluate thick-to-thin conversion for NAS data disks (reduce snapshot size)

### 2. Backup Copy Jobs
- Implement Veeam Backup Copy between internal and external servers
- Create offsite backup rotation to external drive (NVME2)
- Test restore procedures from both repositories

### 3. DR Script Integration
- Document backup task timing for DR script configuration
- Set DR script wait timeout: 15 minutes (max backup time + buffer)
- Test battery-triggered shutdown during backup operations

### 4. Resource Scaling
- Monitor long-term trends (VM growth, backup sizes)
- Consider increasing NAS VM to 10-12GB if utilization exceeds 80%
- Evaluate splitting NFS storage across multiple VMs if I/O becomes bottleneck

---

## Summary

**Optimal Configuration:**
- Transport Mode: Direct Storage Access (DSA)
- Concurrent Tasks: 1
- NAS VM Memory: 9GB
- Expected Backup Time: 4-6 minutes per VM
- Network Throttling: 250 MB/s (optional)

**Key Success Factors:**
1. Single concurrent task prevents disk I/O saturation
2. NAS VM has sufficient memory buffer (9GB)
3. Direct storage access provides optimal speed/stability balance
4. Backup gaps accommodate DR script logic
5. Dual Veeam architecture handles 16-VM environment

**Next Steps:**
1. Implement aggressive backup schedule (7+4 VMs over 2 hours) // 
2. Test NAS VM snapshot in isolated environment ## As tested , never do that while nas running , long stun and whole env stun just in snapshot creation sttep , 
NAS to be excluded from the auto backup , just offline in maintaince windows if needed. 

Have one NAS also saved locally on vcneter snapshot while nas offline  

# backup pfsense run so quick, 1 packet loss only , things stable 

the transfeerr of backup to  windows host veeam done over network with limited speed range 70 - 150 MB without limitation configured, 
so the veeam backup - down time while no running tasks as it will take time 
NAS VM need to take it while offline or while no running VM on it and usually in production this is not possibnle so later need to find a way 
Vcneter , prefer to use the self backup of vcneter and save it to the SMB of windows , or take backup while vcneter offline also, the stun is risky because vcneter will go into self loop , dont backup it with veeam, use esxi self snapshot 
but u may test later 
# dont take esxi production vm with veeam unless no oprtioan run insiode, dont stun with high impact in production , 

3. Configure DR script with 15-minute wait timeout 
4. Monitor production backup operations for first week
5. Document any edge cases or performance anomalies

---

**Related Documentation:**
- Storage Architecture: [04-Storage-Architecture.md](../../../00-DOCUMENTATION/04-Storage-Architecture.md)
- NAS VM Configuration: [04-Storage-Architecture.md#NAS-VM-Storage-Configuration](../../../00-DOCUMENTATION/04-Storage-Architecture.md#NAS-VM-Storage-Configuration)
- Resource Allocation: [02-Resource-Allocation.md](../../../00-DOCUMENTATION/02-Resource-Allocation.md)
