# Storage Performance and Monitoring

> **NFS tuning, disk I/O optimization, and health monitoring**

---

## NFS Performance Tuning

### NAS VM Resources

**Memory**: 9GB (increased from 8GB)
- **Reason**: NFS caching, filesystem metadata
- **Impact**: Reduced I/O storms under load
- **Reference**: See troubleshooting case [05-nas-memory-starvation.md](../../troubleshooting/storage/05-nas-memory-starvation.md)

**CPU**: 2 vCPU
- **Reason**: NFS daemon threading, concurrent I/O
- **Impact**: Better multi-client performance

### Network Bonding

**Configuration:**
- Mode: Active-Backup (HA)
- miimon: 100ms (fast failover)
- Interfaces: 2 vNICs

**Benefit:**
- ✅ Zero downtime during single NIC failure
- ✅ Automatic failover without manual intervention
- ✅ Network-level redundancy for storage traffic

### NFS Mount Options (ESXi)

```
Read Size: 65536 bytes (64KB)
Write Size: 65536 bytes (64KB)
Protocol: NFS 3
```

**Why NFSv3?**
- ✅ Better ESXi compatibility
- ✅ Lower overhead than NFSv4
- ✅ Adequate for home lab use
- ✅ Simpler troubleshooting

---

## Disk I/O Optimization

### ESXi Settings

```
VMFS Block Size: 1MB (default)
Queue Depth: 32 (default)
I/O Scheduler: Deadline (default)
```

**Why defaults work:**
- ✅ Tuned for virtual workloads
- ✅ Balanced for mixed I/O patterns
- ✅ No change needed unless specific bottleneck

### NAS VM Settings

**Filesystem**: ext4
- ✅ Proven stability
- ✅ Good performance for NFS
- ✅ Widely supported and documented

**I/O Scheduler**: cfq (Completely Fair Queuing)
```bash
# Verify I/O scheduler
cat /sys/block/sdb/queue/scheduler
# Expected: [cfq] noop deadline
```

**Read-ahead**: 256KB
```bash
# Check read-ahead
blockdev --getra /dev/sdb
# Expected: 512 (sectors) = 256KB
```

---

## Storage Monitoring

### Datastore Capacity Alerts

**vCenter Alarms:**
```
Alarm: Datastore Disk Usage
Trigger: Datastore Disk Overallocation (%)
Warning: 70%
Critical: 85%
Action: Send email, log event
```

### NFS Health Checks

**Check NFS Exports:**
```bash
# On NAS VM
sudo exportfs -v

# Expected output:
# /mnt/shared_storage 10.0.20.0/24(rw,sync,no_root_squash,no_subtree_check)
# /mnt/datastor2      10.0.20.0/24(rw,sync,no_root_squash,no_subtree_check)
```

**Check ESXi NFS Mounts:**
```bash
# SSH to ESXi
esxcli storage nfs list

# Expected: Both NAS_DS_1 and NAS_DS_2 mounted and accessible
```

### Resource Monitoring

**Memory Usage:**
```bash
# On NAS VM
free -h

# Watch for:
# - Available memory > 2GB
# - Swap usage < 100MB
# - Cache usage healthy
```

**Disk I/O:**
```bash
# Monitor disk I/O performance
iostat -x 5

# Key metrics:
# - %util < 80% (healthy)
# - await < 10ms (good latency)
# - r/s + w/s = IOPS
```

**Network Throughput:**
```bash
# Monitor NFS network traffic
iftop -i bond0

# Watch for:
# - Even distribution across clients
# - No packet loss
# - Bandwidth utilization
```

---

## Performance Baselines

### Expected Performance

**Sequential Read:**
- NVMe: ~2000-3000 MB/s
- VMDK: ~1500-2000 MB/s
- NFS: ~500-800 MB/s

**Sequential Write:**
- NVMe: ~1500-2500 MB/s
- VMDK: ~1000-1500 MB/s
- NFS: ~400-600 MB/s

**Random IOPS (4K):**
- NVMe: ~100K-200K IOPS
- VMDK: ~50K-100K IOPS
- NFS: ~10K-20K IOPS

**Latency:**
- NVMe: < 1ms
- VMDK: 1-3ms
- NFS: 3-10ms

---

## Troubleshooting Performance Issues

### Symptom: Slow VM Disk Performance

**Check Datastore Capacity:**
```bash
# SSH to ESXi
df -h /vmfs/volumes/datastore

# Action: If > 85% full, free up space
```

**Check NAS VM Resources:**
```bash
# On NAS VM
top
free -h

# Action: If memory low, increase NAS VM RAM
```

**Check Network Bonding:**
```bash
# On NAS VM
cat /proc/net/bonding/bond0

# Verify: Both interfaces active, no errors
```

### Symptom: NFS Mount Timeouts

**Check NFS Service:**
```bash
# On NAS VM
systemctl status nfs-server

# Action: Restart if not running
sudo systemctl restart nfs-server
```

**Check Firewall:**
```bash
# On NAS VM
sudo firewall-cmd --list-services

# Expected: nfs, rpc-bind, mountd
```

**Check ESXi Connectivity:**
```bash
# SSH to ESXi
vmkping 10.0.20.90

# Expected: < 1ms latency, 0% loss
```

### Symptom: High I/O Wait

**Identify Bottleneck:**
```bash
# On NAS VM
iostat -x 5

# If %util > 90%: Disk bottleneck
# If await > 50ms: Slow disk or overload
```

**Check for Heavy I/O VMs:**
```bash
# SSH to ESXi
esxtop
# Press 'd' for disk view
# Sort by DAVG (latency)

# Action: Migrate heavy I/O VM to different datastore if needed
```

---

## Monitoring Tools

### Built-in Tools

**ESXi:**
- esxtop (real-time performance)
- vSphere Client performance charts
- Storage views

**NAS VM:**
- iostat (disk I/O)
- iftop (network)
- htop (CPU/memory)
- dstat (all-in-one)

### Future Monitoring Platform

**Planned:**
- Prometheus for metrics collection
- Grafana for visualization
- Node exporter on NAS VM
- VMware exporter for ESXi metrics

**Metrics to Track:**
- Datastore capacity and growth rate
- NFS latency and throughput
- Disk I/O utilization
- Network throughput per datastore

---

## Related Documentation

- [NAS Configuration](03-NAS-Configuration.md)
- [Troubleshooting](07-Troubleshooting.md)
- [ESXi Datastores](02-ESXi-Datastores.md)
- [Platform Layer - Monitoring](../../02-Platform-Layer/)
