================================================================================
DESIGN DECISIONS & RATIONALE
Disaster Recovery Guide - Part 6
================================================================================
Last Updated: 2026-01-03
Back to: [README.md](README.md)

This document explains the "why" behind all major architectural decisions.

================================================================================
TABLE OF CONTENTS
================================================================================
1. Why Standalone ESXi for Outer Layer Backups?
2. Why No Backup Copy Jobs?
3. Why Hard Kill Veeam Jobs?
4. Why 75% Battery Threshold?
5. Why Internal Network (10.0.20.x)?
6. Why Not Use vCenter Snapshots?
7. Why Two Veeam Servers?

================================================================================
1. WHY STANDALONE ESXI FOR OUTER LAYER BACKUPS?
================================================================================

**Decision:** Inner Veeam connects directly to standalone ESXi Master (10.0.20.100)
for ALL outer layer VM backups, NOT through vCenter

## Architecture

```
Inner Veeam (10.0.20.195)
    ↓
ESXi Master (10.0.20.100) [Standalone Direct Connection]
    ↓
├─ IPA
├─ pfSense
├─ NAS
├─ Production ESXi (nested)
├─ DR ESXi (nested)
├─ vCenter ← NOTE: Backed up via ESXi, not through itself
└─ Veeam (Inner)
```

## Reasons

### 1. Eliminates Circular Dependency

**Problem:** Backing up vCenter through vCenter API creates dependency loop

- vCenter manages itself during backup
- vCenter issues = all outer layer backups fail
- vCenter shutdown/restart during backup window = cascade failure

**Solution:** Direct ESXi connection removes vCenter from backup path

- ESXi provides VM access independent of vCenter
- vCenter can be offline/restarting without affecting backup operations
- Breaks the circular dependency completely

### 2. Prevents VM Stun Issues

**VM Stun:** Brief VM freeze during snapshot operations when coordinating through vCenter

- More pronounced on infrastructure VMs (NAS, pfSense, IPA)
- Critical services (DNS, network, storage) affected
- Direct ESXi connection minimizes snapshot coordination overhead

**Impact:**
- vCenter-based: Veeam → vCenter API → ESXi → VM (multiple API hops)
- Direct ESXi: Veeam → ESXi → VM (single API hop, less stun risk)

### 3. DR Resilience During Emergency Shutdown

**Scenario:** Emergency shutdown sequence (Phase 2-4)

- If vCenter is shutting down or has issues during DR event
- Inner Veeam can still access ESXi directly to kill backup jobs
- No dependency on vCenter API availability during critical shutdown window

**Example:**
```
Battery Critical → Kill Backup Jobs
   ↓
Inner Veeam tries to stop backup of IPA
   ↓
If using vCenter: vCenter might be shutting down → FAIL
If using ESXi direct: ESXi still running → SUCCESS
```

### 4. Simplified Architecture

**Single ESXi Master Host:**

- Not a cluster (no vMotion, no DRS)
- VMs have static placement (never migrate between hosts)
- No dynamic orchestration features
- Lab environment, not production datacenter

**When vCenter Would Be Better:**

- Multi-host clusters with vMotion (VMs moving between hosts)
- Complex backup job organization using vCenter tags/folders
- vCenter-aware application processing requirements

**None of these apply to this environment.**

### 5. Consistency Across Backup Architecture

**Principle:** Match connection method to environment layer

- Outer Veeam → Uses vCenter (Production ESXi nested, manages 10 VMs)
- Inner Veeam → Uses standalone ESXi (ESXi Master, single host)

**Why the difference?**

- Production ESXi layer: vCenter manages these VMs (application layer)
- ESXi Master layer: Single host, no vCenter orchestration needed
- Using vCenter for outer layer adds dependency without benefit

### 6. Avoids vCenter Backup Conflicts

**Potential Issue:** vCenter backing up itself through its own API

- Inventory operations during backup
- Database locks during snapshot
- Configuration changes mid-backup
- Self-referential API calls

**Direct ESXi:** Treats vCenter as regular VM (no special API interactions)

## Implementation Notes

**Veeam Configuration:**
1. Add ESXi Master (10.0.20.100) as "Managed Server"
2. Use ESXi root credentials (not vCenter credentials)
3. Create backup jobs pointing to ESXi Master inventory
4. Select VMs from ESXi view (not vCenter view)

**Trade-offs:**
- Lose vCenter-aware features (tags, folders, DRS awareness)
- Gain: Reliability, independence, simpler DR coordination
- For this environment: Trade-off heavily favors direct ESXi

================================================================================
2. WHY NO BACKUP COPY JOBS?
================================================================================

**Decision:** Rejected Veeam Backup Copy Jobs for replicating Inner Veeam
backups to Outer Veeam repository

## Reasons for Rejection

### 1. Complexity ("Spaghetti" Architecture)

- Primary backup jobs: 10 jobs total (7 Inner Veeam + 3 Outer Veeam automated)
- Backup copy jobs: Would add 7 more jobs (one per outer layer VM)
- Total: 17 jobs to monitor, schedule, and troubleshoot

### 2. Performance and Resource Overhead

- Additional I/O load on NAS (reading backup files to send to copy job)
- Network traffic from Inner Veeam to Outer Veeam (crosses VM boundary)
- Extended backup window (primary backup → backup copy → completion)

**Example Timeline:**
```
Without Backup Copy:
7:50 PM: pfSense backup starts
8:00 PM: pfSense backup completes (10 min)

With Backup Copy:
7:50 PM: pfSense backup starts
8:00 PM: pfSense backup completes
8:00 PM: Backup copy job starts
8:15 PM: Backup copy completes (15 min for transfer)

Result: 50% longer backup window per job
```

### 3. Storage Duplication

- Inner layer backups: ~300 GB total (estimated)
- Backup copy would consume additional 300 GB on Windows Host
- Lab laptop has limited storage
- Cost/benefit analysis: Doubling storage for lab environment not justified

### 4. Limited Benefit for Lab Environment

**This is NOT production:**
- Acceptable data loss window: Days (not hours)
- No SLA requirements
- Can rebuild from older backups if needed

### 5. Job Scheduling Conflicts

During DR event, all running jobs must be killed immediately.

With backup copy jobs:
- Primary job might be complete
- Backup copy job might be running
- Two jobs to kill instead of one
- More complexity during critical DR window

## What We Actually Do Instead

**For Inner Veeam Configuration:**
- Outer Veeam backs up Inner Veeam VM (all disks)
- Captures: Veeam database, job configs, metadata
- Stored on: Windows Host (separate from NAS)

**For Backup Data:**
- Inner Veeam backups stored on NAS only (single copy)
- Risk accepted: NAS failure = lose outer layer backup history
- Mitigation: NAS VM itself backed up

**For Inner Layer (Application VMs):**
- Outer Veeam backs up K8s, Vault, Jenkins, etc.
- Stored on: Windows Host (completely separate)
- Protection level: Higher (these are harder to rebuild)

**Conclusion:** For lab environment, simplicity and resource efficiency outweigh
redundancy benefits.

================================================================================
3. WHY HARD KILL VEEAM JOBS?
================================================================================

**Decision:** Immediate termination instead of graceful stop during DR

## Testing Results

- Graceful stop during disk block transfer: Waits indefinitely
- Tested scenarios: 50GB VM backup at 80% completion
- Soft stop waited: 45+ minutes for single block completion
- Hard stop completed: Immediately (job state: "Stopping")

## Risk Assessment

- Corrupted backup: Repairable via Veeam health check
- Complete data loss: Unrecoverable
- Battery runtime: 15-20 minutes at 75% threshold
- Full shutdown: 10-13 minutes required

**Conclusion:** Corrupted backup (recoverable) < total data loss (unrecoverable)

## Implementation

**Graceful Stop (REJECTED):**
```powershell
Stop-VBRJob -Job $Job -Gracefully
# Waits for current block to finish - can take hours
```

**Hard Kill (CHOSEN):**
```powershell
Stop-VBRJob -Job $Job
# NO -Gracefully flag = immediate termination
```

## What Happens to Backup?

**After Hard Kill:**
- Backup chain may need repair
- Veeam has built-in health check and repair tools
- Next backup will detect issue and fix
- Restore points before kill remain valid

================================================================================
4. WHY 75% BATTERY THRESHOLD?
================================================================================

**Decision:** Trigger emergency shutdown at 75% battery (when discharging)

## Analysis

- Battery capacity: ~60 Wh (laptop dependent)
- Runtime at 75%: ~15-20 minutes remaining
- Shutdown sequence: 10-13 minutes required
- Buffer: 5-7 minutes safety margin

## Considerations

- Higher threshold (80%): More safety, more false triggers
- Lower threshold (70%): Less safety, tighter timing
- 75% chosen: Balance between safety and practicality

## Timing Breakdown

**Total Shutdown Sequence:**
- Phase 2: < 1 minute (Veeam kills)
- Phase 3: 3 minutes (nested ESXi)
- Phase 4: 3 minutes (master ESXi)
- Phase 5: 3 minutes (fallback if needed)
- Phase 6: Instant

**Total:** 10-13 minutes maximum
**Available:** 15-20 minutes at 75%
**Safety Margin:** 5-7 minutes

================================================================================
5. WHY INTERNAL NETWORK (10.0.20.x)?
================================================================================

**Decision:** Critical infrastructure on isolated internal network

## Problem: Power Outage Scenarios

- Home router (<GATEWAY_IP>): Loses power immediately
- Network switches: Lose power immediately
- Result: External network (192.168.0.x) unavailable

## Solution: VMware Workstation Internal vSwitch

- Exists entirely in software on laptop
- No dependency on physical network hardware
- Survives as long as laptop battery alive
- VMs can communicate for shutdown coordination

## Implementation

**Critical Infrastructure on 10.0.20.x:**
- vCenter: 10.0.20.89 (must coordinate shutdown)
- ESXi hosts: 10.0.20.x (must receive shutdown signals)
- pfSense: Bridge between 192.168.0.x and 10.0.20.x (NAT)

**Result:** DR script can reach all components during power outage

================================================================================
6. WHY NOT USE VCENTER SNAPSHOTS?
================================================================================

**Decision:** No automated vCenter snapshots; rely exclusively on Veeam

## Reasons

### 1. Snapshots ≠ Backups

- Snapshots are delta files on same storage (single point of failure)
- Storage failure = loss of base disk AND snapshots
- Veeam = separate backup repository (true backup)

### 2. Performance Impact

- Snapshots reduce VM performance (delta file I/O overhead)
- Snapshot chains grow over time (compounding slowdown)
- Veeam uses changed block tracking (minimal performance impact)

### 3. Veeam + Snapshot Conflicts

- Veeam creates temporary snapshots during backup
- Existing snapshots can interfere with Veeam operations
- Risk of snapshot chain corruption during backup

### 4. Power Loss Complexity

- Snapshots during power cut = potential chain corruption
- Snapshot consolidation requires I/O (time we don't have)
- Clean Veeam backup = faster restore path

### 5. Management Overhead

- Snapshots require manual consolidation
- Snapshot chain monitoring needed
- Veeam handles retention automatically

## When to Use vCenter Snapshots

**Policy:** Manual snapshots ONLY before critical operations

**Use Cases:**
- Before major configuration changes (network, storage, certificates)
- Before software updates (vCenter, ESXi, critical VMs)
- Before infrastructure migrations (IP changes, NIC modifications)

**Snapshot Procedure:**

1. **Before Critical Operation:**
   - Take snapshot via vCenter
   - Name: "Pre-[operation]-[date]"
   - Description: Include what you're about to do
   - Snapshot memory: No
   - Quiesce guest: Yes (if VMware Tools installed)

2. **Retention Period:** 2-3 days minimum

3. **Validation Before Deletion:**
   - System running normally for 2-3 days
   - No errors in logs
   - Veeam backups completed successfully

**Never Use Snapshots For:**
- Long-term backups (use Veeam)
- Automated daily snapshots (conflicts with Veeam)
- Multiple snapshots per VM (complex chain management)

================================================================================
7. WHY TWO VEEAM SERVERS?
================================================================================

**Decision:** Separate Veeam instances for inner and outer layers

## Drivers

1. **Licensing:** Veeam Community Edition = 10 VM limit per instance
2. **Segmentation:** 10 VMs on inner + 7 VMs on outer = 17 total
3. **Isolation:** Outer Veeam survives inner infrastructure failure
4. **Performance:** Distribute backup load across two servers

## Trade-offs

**Pros:**
- Complete infrastructure coverage within free licensing
- Isolation (one Veeam failure doesn't affect other layer)
- Load distribution

**Cons:**
- Complexity: Two servers to manage
- Storage: Two backup repositories

**Benefit:** Complete infrastructure coverage within free licensing constraints

## Cross-Protection

**Inner Veeam VM Backed Up by Outer Veeam:**
- Outer Veeam backs up the Inner Veeam VM itself
- Protects Veeam configuration and job definitions
- Enables recovery of Inner Veeam if it fails
- Stored on Windows Host (separate from NAS)

================================================================================
SUMMARY
================================================================================

All design decisions prioritize:
1. **Simplicity** over complexity
2. **Reliability** over features
3. **Independence** over convenience
4. **Lab practicality** over production best practices

These are conscious trade-offs appropriate for a lab environment where:
- Downtime is acceptable
- Recovery can be manual
- Simplicity aids troubleshooting
- Resource constraints are real

================================================================================
RELATED DOCUMENTATION
================================================================================

- [01-Backup-Strategy.md](01-Backup-Strategy.md) - Implementation of these decisions
- [03-Emergency-Shutdown.md](03-Emergency-Shutdown.md) - Hard kill implementation
- [05-Recovery-Procedures.md](05-Recovery-Procedures.md) - Standalone ESXi recovery

Back to: [README.md](README.md)
