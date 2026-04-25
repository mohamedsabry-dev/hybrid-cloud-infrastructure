# Resource Optimization Best Practices

> **Memory management, CPU optimization, and Windows host stability**

---

## Memory Management Best Practices

### General Guidelines

**DO:**
- Leave 1-2GB headroom for unexpected spikes
- Monitor actual usage vs allocated (adjust as needed)
- Calculate worst-case memory requirements before deployment
- Test resource allocation under realistic workloads
- Reserve adequate memory for Windows host (8GB minimum)

**DON'T:**
- Don't assume ESXi releases memory after VM migration
- Don't run production without buffer memory
- Don't allocate 100% without testing first
- Don't ignore swap usage on Windows host

### Memory Monitoring

**ESXi Host Level:**
```bash
# Check memory usage
esxtop
# Press 'm' for memory view
# Watch: %ACTV (active memory), SWCUR (swap current)
```

**VM Level:**
```bash
# Inside VM
free -h
top

# Watch for:
# - Available memory > 500MB
# - Swap usage < 100MB
# - No OOM killer events
```

---

## CPU Over-Commitment Guidelines

### Safe Over-Commitment Levels

**Infrastructure Layer (ESXi Master):**
- Over-commitment: 194% (31 vCPU / 16 physical)
- Safe because: Complementary workloads (backup vs management vs storage)
- Monitoring: Host CPU should stay < 50% average

**Production Layer (Nested ESXi):**
- Over-commitment: 230% (23 vCPU / 10 allocated)
- Safe because: Most VMs idle or <40% utilization
- Monitoring: Nested ESXi CPU should stay < 60% average

### What Makes Over-Commitment Safe

**Complementary Workloads:**
- Veeam peaks during backup window (2-4 AM)
- Ansible peaks during playbook runs (manual)
- Jenkins peaks during builds (triggered)
- K8s workloads: Bursty, not sustained

**High-Frequency CPU:**
- 3.1GHz+ base frequency
- Handles context switching efficiently
- ESXi scheduler optimized for over-commit

### CPU Monitoring

**ESXi Host Level:**
```bash
# Check CPU usage
esxtop
# Press 'c' for CPU view
# Watch: %USED (CPU utilization), %RDY (ready time)

# Ready time > 5% indicates CPU contention
```

**VM Level:**
```bash
# Inside VM
top
htop

# Watch for:
# - Load average < number of vCPUs
# - CPU steal time < 5%
```

---

## Storage Planning Best Practices

### Provisioning Strategy

**Use Thick Provisioning When:**
- Critical storage infrastructure (NAS VM)
- Predictable performance required
- Dedicated datastore available for snapshots

**Use Thin Provisioning When:**
- Most VMs (flexibility + efficiency)
- Snapshots needed frequently
- Space efficiency important

### Snapshot Planning

**Before Creating Snapshot:**
1. Calculate required space (1.5x disk usage for thin, 1.5x capacity for thick)
2. Verify datastore has sufficient free space
3. Plan deletion within 24-48 hours

**DON'T:**
- Keep snapshots longer than 1 week
- Use snapshots as backups (use Veeam)
- Take snapshot without verifying free space

---

## Windows Host Settings and Stability

### Recommended Configuration

```
Memory: 64GB @ 4800MHz
Reserved: 8GB for Windows (prevents swap usage)
Swap: 32GB on NVMe (emergency buffer only)
Hibernation: DISABLED
  └─ Prevents memory corruption
  └─ Normal shutdown after work
  └─ Reduces cache inconsistencies
```

###  IMPORTANT: Windows Host Stability Warning

**Issue:** When running the full environment alongside development tools, the Windows host experiences significant memory pressure and swap usage.

**Symptoms:**
```
Environment Running:     ~56GB (ESXi Master + Infrastructure + Production)
VSCode:                  ~1-2GB
Web Browser (Edge/Chrome): ~1-2GB
MobaXterm:              ~0.5GB
Wireshark:              ~0.5GB
───────────────────────────────────────
Total Memory Demand:    ~59-61GB
Physical RAM Available:  64GB
Windows Reserved:        8GB
═══════════════════════════════════════
Result: Windows forces 6-7GB to SWAP
```

**Impact:**
- Laptop performance degradation
- Increased disk I/O on NVMe
- System responsiveness issues
- Potential stability concerns

---

## Recommended Solutions for Host Stability

### Option 1: Use Separate Laptop for Operations (Recommended)

```
Laptop 1: Run full DC-K8s environment only
Laptop 2: Run VSCode, browsers, development tools
Benefits:
  Yes No swap usage on either system
  Yes Stable environment performance
  Yes No interference between workloads
```

**When to Use:**
- Full production testing
- Extended lab sessions
- Performance-critical operations
- Recording/documenting work

---

### Option 2: Reduce Resource Allocation

```
If using single laptop, consider reducing:
  ├─ Production ESXi: 29GB → 24-26GB
  ├─ Shutdown non-essential VMs during development:
  │   └─ Jenkins, Grafana, or 1 K8s worker
  └─ Close heavy applications when not needed
Benefits:
  Yes Reduces swap pressure
  Yes Maintains core functionality
   Loses some production-like environment features
```

**When to Use:**
- Development work with some lab services
- Testing specific components
- Single-laptop workflow required

---

### Option 3: Close Development Tools During Full Environment Testing

```
When testing full production environment:
  ├─ Close VSCode
  ├─ Close web browsers (keep 1 tab for vCenter only)
  ├─ Stop MobaXterm when not actively using
  └─ Stop Wireshark captures
Benefits:
  Yes Full environment can run without swap
   Cannot develop/monitor simultaneously
```

**When to Use:**
- DR testing
- Cluster failover testing
- Full environment validation
- Capacity testing

---

## Resource Optimization Checklist

### Before Deployment

**Memory:**
- [ ] Calculate total memory requirements
- [ ] Add 1-2GB buffer
- [ ] Verify Windows host has 8GB reserved
- [ ] Test under realistic load

**CPU:**
- [ ] Plan for over-commitment < 250%
- [ ] Identify complementary workloads
- [ ] Monitor host CPU during testing

**Storage:**
- [ ] Choose provisioning type (thin vs thick)
- [ ] Plan snapshot space requirements
- [ ] Verify datastore capacity

### During Operations

**Weekly Checks:**
- [ ] Review memory usage trends
- [ ] Check for swap usage on VMs
- [ ] Monitor CPU ready time
- [ ] Review datastore capacity

**Monthly Reviews:**
- [ ] Analyze resource utilization reports
- [ ] Identify under/over-allocated VMs
- [ ] Plan capacity adjustments
- [ ] Test DR activation

---

## Testing and Validation

### Resource Usage Testing Results

**Full Environment Running:**
- Host CPU usage: ~30% average
- Host CPU during backups: 35-40%
- Memory balloon: Stable, no swapping
- Storage I/O: No bottlenecks observed

**DR Testing:**
- Power on DR for maintenance windows
- Live migrate VMs to DR (manual process)
- Enter Production into maintenance mode
- Return to normal after testing

### Performance Benchmarks

**ESXi Master Performance:**
```
CPU Utilization: 30-40% average
Memory Usage: 53-54GB / 56GB
Disk I/O: <50% utilization
Network: <30% utilization
```

**Production ESXi Performance:**
```
CPU Utilization: 20-30% average
Memory Usage: 26-27GB / 29GB
Ready Time: <2% (excellent)
```

---

## Current Configuration Note

The current resource allocation (64GB total) is designed for running the **full production environment** OR **development tools**, but NOT both simultaneously on a single laptop without swap usage.

**Recommended Workflow:**
1. Use separate laptop for operations (ideal)
2. OR shut down non-essential VMs when developing
3. OR close development tools when testing full environment

---

## Related Documentation

- [Resource Overview](01-Resource-Overview.md)
- [VM Specifications and Decisions](02-VM-Specifications-and-Decisions.md)
- [Storage Architecture](../Storage/)
- [Network Architecture](../Network/)
- [Platform Layer](../../02-Platform-Layer/)
