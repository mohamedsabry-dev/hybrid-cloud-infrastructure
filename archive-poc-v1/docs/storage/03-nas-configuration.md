# NAS VM Configuration

> **NAS VM disk mounting, NFS exports, and network configuration**

---

## Overview

**NAS VM**: Rocky Linux 10
**Memory**: 9GB (increased from 8GB for concurrent backup operations)
**CPU**: 2 vCPU
**Network**: 2 vNIC bonded (Active-Backup)

---

## Disk Configuration

```
NAS VM Disks:
│
├─ /dev/sda - 30GB OS Disk (Thin)
│   └─ Rocky Linux 10 OS
│
├─ /dev/sdb - 900GB Data Disk (Thick)
│   └─ Mounted: /mnt/shared_storage
│       └─ NFS Export: NAS_DS_1
│
└─ /dev/sdc - 5GB Data Disk (Thick)
    └─ Mounted: /mnt/datastor2
        └─ NFS Export: NAS_DS_2
```

---

## Critical: UUID-Based Mounting

### Problem with /dev/sdX Naming

Linux assigns device names based on initialization order, which is NOT guaranteed across reboots. Using /dev/sdX in /etc/fstab can cause disk race conditions.

**Disaster Scenario:**
```
Boot 1:
  /dev/sdb = 900GB disk (Production data)
  /dev/sdc = 5GB disk (Heartbeat)
  Yes Mounts correctly

Reboot:
  /dev/sdb = 5GB disk (swapped!)
  /dev/sdc = 900GB disk (swapped!)
  No 900GB production data mounted as 5GB heartbeat
  No All VMs fail to start
```

### Solution: UUID-Based Mounting

**Get disk UUIDs:**
```bash
# Get UUID for 900GB disk
sudo blkid /dev/sdb
# Output: UUID="a1b2c3d4-e5f6-7890-abcd-ef1234567890"

# Get UUID for 5GB disk
sudo blkid /dev/sdc
# Output: UUID="f1e2d3c4-b5a6-7890-fedc-ba0987654321"
```

**Correct /etc/fstab:**
```bash
# 900GB Production Storage (UUID-based)
UUID=a1b2c3d4-e5f6-7890-abcd-ef1234567890  /mnt/shared_storage  ext4  defaults  0 0

# 5GB Heartbeat Storage (UUID-based)
UUID=f1e2d3c4-b5a6-7890-fedc-ba0987654321  /mnt/datastor2  ext4  defaults  0 0
```

**Verification Before Reboot:**
```bash
# CRITICAL: Test fstab before rebooting
sudo findmnt --verify

# Expected: No errors
# If errors found: DO NOT REBOOT (VM won't start)
```

**Reference:** See troubleshooting case [03-disk-race-condition-disaster.md](../../troubleshooting/storage/03-disk-race-condition-disaster.md)

---

## NFS Export Configuration

**Export File**: `/etc/exports`

```bash
# NFS Exports for ESXi
/mnt/shared_storage  10.0.20.0/24(rw,sync,no_root_squash,no_subtree_check)
/mnt/datastor2       10.0.20.0/24(rw,sync,no_root_squash,no_subtree_check)
```

### NFS Options Explained

| Option | Purpose |
|--------|---------|
| **rw** | Read-write access |
| **sync** | Write operations complete before confirming (data safety) |
| **no_root_squash** | Allow ESXi root user to have root privileges (required) |
| **no_subtree_check** | Disable subtree checking (better performance) |
| **10.0.20.0/24** | Restrict access to internal network only (security) |

### Apply Export Configuration

```bash
# Export all filesystems
sudo exportfs -av

# Restart NFS server
sudo systemctl restart nfs-server

# Verify exports
sudo exportfs -v
```

---

## Firewall Configuration

```bash
# Allow NFS traffic
sudo firewall-cmd --permanent --add-service=nfs
sudo firewall-cmd --permanent --add-service=rpc-bind
sudo firewall-cmd --permanent --add-service=mountd
sudo firewall-cmd --reload
```

---

## Network Bonding

**Bonding Mode**: Active-Backup (HA)
**Interfaces**: 2 vNICs
**Monitoring Interval**: 100ms (fast failover)

**Benefits:**
- Zero downtime during single NIC failure
- Automatic failover to backup interface
- No manual intervention required

**Configuration:**
See [Network Architecture](../Network/) for bonding setup details.

---

## NFS Health Monitoring

### Check NFS Exports

```bash
# On NAS VM
sudo exportfs -v

# Expected: Both shares exported
# /mnt/shared_storage  10.0.20.0/24(rw,sync,no_root_squash,no_subtree_check)
# /mnt/datastor2       10.0.20.0/24(rw,sync,no_root_squash,no_subtree_check)
```

### Check ESXi NFS Mounts

```bash
# SSH to ESXi
esxcli storage nfs list

# Expected: Both NAS_DS_1 and NAS_DS_2 mounted
```

### Monitor NAS VM Resources

```bash
# Memory usage
free -h

# Disk I/O
iostat -x 5

# Network throughput
iftop -i bond0
```

---

## Related Documentation

- [ESXi Datastores](02-ESXi-Datastores.md)
- [Performance Monitoring](06-Performance-Monitoring.md)
- [Troubleshooting](07-Troubleshooting.md)
- [Troubleshooting Cases](../../troubleshooting/storage/)


