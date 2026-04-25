# Snapshot Management and Backup Strategy

> **VMware snapshot best practices and Veeam backup configuration**

---

## Snapshot Best Practices

**DO:**
- Take snapshots before risky operations
- Delete snapshots within 24-48 hours
- Calculate required space before creating
- Test VM boot after snapshot deletion
- Use Veeam for long-term backups (not snapshots)

**DON'T:**
- Keep snapshots longer than 1 week
- Accumulate more than 2-3 snapshots per VM
- Use snapshots as backups
- Take snapshots without verifying free space
- Ignore datastore space warnings

---

## Snapshot Space Calculation

### Thin Provisioned VMs

```
Required Space = Actual Data Usage × 1.5

Example:
  VM: 100GB allocated, 30GB used
  Snapshot: 30GB × 1.5 = 45GB required
```

### Thick Provisioned VMs

```
Required Space = Provisioned Capacity × 1.5

Example:
  NAS VM: 905GB thick provisioned (data disks only)
  Snapshot: 905GB × 1.5 = 1358GB required
  Datastore: DS_NVME_2 = 2TB Yes (sufficient space)
```

**Why 1.5x Multiplier?**
- 1.0x for snapshot delta disks
- 0.3x for metadata and overhead
- 0.2x for consolidation working space

---

## Snapshot Operations

### Create Snapshot (vCenter)

```
1. Right-click VM
2. Snapshots > Take Snapshot
3. Name: "Before_RAID_Config" (descriptive)
4. Description: Purpose and date
5. Yes Snapshot VM memory (optional, for running VMs)
6. Click OK
```

### Delete Snapshot (vCenter)

```
1. Right-click VM
2. Snapshots > Manage Snapshots
3. Select snapshot
4. Click Delete (consolidates changes back to base disk)
5. Wait for consolidation to complete
6. Verify VM still boots
```

### Verify Consolidation

```bash
# SSH to ESXi
cd /vmfs/volumes/datastore/VM_folder/

# List snapshot files
ls -lh *-00*.vmdk

# Expected: No snapshot files remain after deletion
```

---

## Pre-Snapshot Space Check Script

```bash
#!/bin/bash
# pre-snapshot-check.sh

DATASTORE="/vmfs/volumes/datastore1"
FREE_SPACE=$(df -h $DATASTORE | awk 'NR==2 {print $4}' | sed 's/G//')
REQUIRED_SPACE=1515  # Adjust based on VMs

if (( $(echo "$FREE_SPACE < $REQUIRED_SPACE" | bc -l) )); then
  echo "ERROR: Insufficient space for snapshots!"
  echo "Free: ${FREE_SPACE}GB, Required: ${REQUIRED_SPACE}GB"
  exit 1
else
  echo "OK: Sufficient space. Free: ${FREE_SPACE}GB"
  exit 0
fi
```

---

## Veeam Backup Strategy

### Backup Repository

**Primary Repository**: 600GB internal vDisk on DS_NVME_1

**Backup Scope**: All VMs except Veeam itself
- Infrastructure VMs (vCenter, pfSense, NAS)
- Production VMs (K8s, Vault, IPA, Ansible, etc.)

**Schedule:**
```
Daily Incremental: Every night at 2:00 AM
Weekly Full: Sunday at 1:00 AM
Retention: 14 restore points (2 weeks)
Compression: Enabled (dedupe + compression)
```

### Backup Copy Job

**Secondary Repository**: External drive (500GB NVME2)

**Configuration:**
- **Primary**: Internal repository (500GB on DS_NVME_1)
- **Secondary**: External drive (500GB NVME2)
- **Frequency**: Daily after primary job completes
- **Retention**: 4 weeks on external

**Benefits:**
- Offsite protection (removable drive)
- Survives laptop failure
- 3-2-1 backup rule compliance

---

## Snapshots vs Backups

### VMware Snapshots

**Characteristics:**
-  For short-term testing/rollback (hours to days)
-  Depend on original VM and datastore
-  Cannot survive datastore corruption
-  Performance degrades with long snapshot chains
- Yes Fast rollback (seconds to minutes)

**Use Cases:**
- Before applying system updates
- Before configuration changes
- Before software upgrades
- Testing scenarios requiring quick rollback

### Veeam Backups

**Characteristics:**
- Yes For long-term protection (weeks to months)
- Yes Compressed, space-efficient
- Yes Independent from source datastore
- Yes Restore to different infrastructure
- Yes Incremental backup chains
-  Slower restore (minutes to hours)

**Use Cases:**
- Daily production VM protection
- Disaster recovery scenarios
- Migrating VMs to new infrastructure
- Compliance and archival requirements

### Rule of Thumb

```
Snapshot: "I'm about to make a risky change, need quick rollback"
Backup: "I need to protect this VM for the long term"
```

---

## Datastore Capacity Alerts

### vCenter Alarms

```
Alarm: Datastore Disk Usage
Trigger: Datastore Disk Overallocation (%)
Warning: 70%
Critical: 85%
Action: Send email, log event
```

### Monitoring Best Practices

**Weekly Reviews:**
- Check datastore usage trends
- Review snapshot age (delete old ones)
- Verify backup jobs completed
- Monitor thin provisioning ratio

**Before Major Changes:**
- Calculate required snapshot space
- Verify datastore headroom
- Consider temporary cleanup if needed
- Document expected space consumption

---

## Common Snapshot Scenarios

### Scenario 1: Upgrading vCenter

```
1. Calculate: vCenter 500GB allocated, 350GB used
2. Required: 350GB × 1.5 = 525GB
3. Check: DS_NVME_1 has 500GB free Yes
4. Create snapshot: "Before_vCenter_8_Upgrade"
5. Perform upgrade
6. Test: 24-48 hours
7. Delete snapshot if successful
```

### Scenario 2: Testing NAS VM Changes

```
1. Calculate: NAS VM 905GB thick provisioned
2. Required: 905GB × 1.5 = 1358GB
3. Check: DS_NVME_2 has 1065GB free Yes
4. Create snapshot: "Before_NFS_Export_Change"
5. Make changes
6. Test: 2-3 days
7. Delete snapshot after validation
```

### Scenario 3: K8s Cluster Upgrade

```
1. Calculate: K8s Master 110GB, 3 Workers 60GB each
2. Required: (110 + 180) × 1.5 = 435GB
3. Check: NAS_DS_1 has 120GB free No (insufficient)
4. Alternative: Use Veeam backup instead
5. Take Veeam backup before upgrade
6. Proceed with upgrade
7. Verify backups after successful upgrade
```

---

## Related Documentation

- [ESXi Datastores](02-ESXi-Datastores.md)
- [Provisioning and RAID](04-Provisioning-and-RAID.md)
- [Troubleshooting](07-Troubleshooting.md)
- [Backup Strategy](../../02-Platform-Layer/)
