# vMotion Network

> **Dedicated isolated network for ESXi live migration traffic**

---

## Purpose

- **Dedicated** for ESXi vMotion traffic
- Isolated from management and VM traffic
- Prevents I/O contention during live migrations

---

## Network Configuration

**Subnet**: 10.0.30.x/24
**Gateway**: None (isolated network)
**DNS**: None (point-to-point communication only)
**VMware Type**: VMnet3 (Host-Only network)

---

## Why Separate vMotion Network?

### Without Dedicated vMotion

**Problem Scenario:**
```
Management + vMotion + Backup all on 10.0.20.x/24
  │
  ├─ Veeam backing up 50GB VM → High I/O
  └─ vMotion migrating VM → Competes for bandwidth

Result: Slow migration, potential timeout failures
```

### With Dedicated vMotion

**Isolated Traffic:**
```
Management + Backup: 10.0.20.x/24 (Internal Network)
vMotion: 10.0.30.x/24 (Dedicated Network)

No interference between operations
```

**Benefits:**
- vMotion isolated from backup traffic
- No I/O contention during simultaneous operations
- Faster and more reliable live migrations
- Production best practice

---

## ESXi Master - vSwitch_vMotion_OPS

### vSwitch Configuration

**Uplinks**: 1 physical vNIC from VMnet3

**Security Policies:**
- Promiscuous Mode: OFF
- Forged Transmits: OFF
- MAC Changes: OFF

**Portgroup:**
- **vMotion Network**
  - ESXi Master vmk2: 10.0.30.100 (vMotion enabled)

---

## ESXi Production - vSwitch_vMotion

**Portgroup:**
- **vMotion Network**
  - ESXi Production vmk: 10.0.30.101 (vMotion enabled)

---

## ESXi DR - vSwitch_vMotion

**Status**: Cold Standby (Powered OFF)

**Portgroup:**
- **vMotion Network**
  - ESXi DR vmk: 10.0.30.102 (vMotion enabled)

---

## VMkernel Adapter Configuration

### Enable vMotion on VMkernel Adapter

**On each ESXi host:**
1. Navigate to: Networking > VMkernel adapters
2. Edit VMkernel adapter on vMotion network (vmk2 on Master, vmk on nested)
3. Enable: Yes vMotion traffic
4. Disable vMotion on other VMkernel adapters (Management network)

**vCenter GUI:**
```
Host > Configure > Networking > VMkernel adapters > Edit > Services
Yes vMotion
```

### Verification

```bash
# SSH to ESXi
vim-cmd hostsvc/vmotion/vnic_info

# Expected Output:
# IP: 10.0.30.x
# Enabled: true
```

**Example Output:**
```
VMotion VNic:
  Device: vmk2
  Key: key-vim.host.VirtualNic-vmk2
  Portgroup: vMotion Network
  IP: 10.0.30.100
  Netmask: 255.255.255.0
  VMotion enabled: true
```

---

## IP Address Allocation

| IP Address | Hostname | FQDN | VMkernel | Status | Purpose |
|------------|----------|------|----------|--------|---------|
| 10.0.30.100 | esxi-master | esxi-master.home.lab | vmk2 | Active | ESXi Master vMotion |
| 10.0.30.101 | esxi-prod | esxi-prod.home.lab | vmk1 | Active | ESXi Production vMotion |
| 10.0.30.102 | esxi-dr | esxi-dr.home.lab | vmk1 | Powered Off | ESXi DR vMotion |

---

## vMotion Performance Considerations

### Network Requirements

**Minimum Bandwidth**: 1 Gbps (adequate for home lab)
**Recommended for Production**: 10 Gbps

**Current Lab Configuration:**
- VMware Workstation virtual networks (1 Gbps virtual)
- Adequate for ~50-100GB VM migrations in minutes

### vMotion Process

**How vMotion Works:**
1. Copy VM memory state to destination host (10.0.30.x network)
2. Sync storage (via NFS shared datastore - uses 10.0.20.x network)
3. Switch VM execution to destination (millisecond pause)
4. Remove source VM

**Why dedicated network helps:**
- Memory state transfer (largest component) uses dedicated bandwidth
- Management and production traffic unaffected
- Predictable migration time

---

## Testing vMotion

### Basic vMotion Test

**Prerequisites:**
- ESXi Production and DR hosts in same cluster
- Both connected to NAS_DS_1 (shared NFS datastore)
- vMotion network configured on both hosts

**Test Procedure:**
1. Select running VM on ESXi Production
2. Right-click > Migrate
3. Select "Change compute resource only"
4. Select ESXi DR as destination
5. Click Finish

**Expected Result:**
- Migration completes in seconds to minutes (depending on VM memory size)
- VM continues running without interruption
- No noticeable downtime

**Monitoring:**
```bash
# Watch vMotion progress in vCenter
# Tasks & Events panel shows:
# "Relocate virtual machine" - In Progress
# "Relocate virtual machine" - Completed
```

---

## Troubleshooting

### Issue: vMotion Fails with "Network Unreachable"

**Symptom**: vMotion fails immediately with network error

**Cause**: vMotion network not properly configured on source or destination

**Verification:**
```bash
# On both ESXi hosts
vim-cmd hostsvc/vmotion/vnic_info

# Verify both show vMotion enabled on 10.0.30.x network
```

**Solution:**
1. Verify VMkernel adapter exists on vMotion network (10.0.30.x)
2. Verify vMotion service enabled on adapter
3. Test connectivity: `vmkping -I vmk2 10.0.30.101`

### Issue: vMotion Slow or Times Out

**Symptom**: vMotion takes extremely long or times out

**Cause**: Network congestion on management network (vMotion using wrong network)

**Verification:**
```bash
# Check which interface vMotion is using
esxtop
# Press 'n' for network view
# Look for high traffic on vmk1 during vMotion (wrong!)
```

**Solution**:
- Ensure vMotion **disabled** on management VMkernel (vmk1)
- Ensure vMotion **enabled** only on vMotion VMkernel (vmk2)

---

## Future Enhancements

**10 Gbps vMotion Network:**
- When upgrading physical network hardware
- Faster migrations for large VMs (>100GB memory)
- Support for simultaneous migrations

**Multi-NIC vMotion:**
- Configure multiple VMkernel adapters for vMotion
- ESXi automatically load balances across NICs
- Higher aggregate bandwidth

---

## Related Documentation

- [Network Overview](01-Network-Overview.md)
- [Internal Network](03-Internal-Network.md)
- [Network Security](07-Network-Security-and-Troubleshooting.md)
- [Compute Resources](../Compute/)
