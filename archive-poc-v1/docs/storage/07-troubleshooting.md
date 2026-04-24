# Storage Troubleshooting Guide

> **Common storage issues, solutions, and references to detailed troubleshooting cases**

---

## Common Storage Issues

### Issue 1: VMDK Snapshot Chain Corruption

**Symptoms:**
- VM won't boot after snapshot deletion
- Error: "Parent virtual disk has been modified"
- Datastores show as "inaccessible"

**Cause:**
Parent VMDK and child delta disks stored in different directories/drives.

**Solution:**
Keep all VM files in same directory. If corrupted, manually rebuild descriptor file.

**Detailed Reference:** [07-vmware-snapshot-chain-corruption.md](../../troubleshooting/storage/07-vmware-snapshot-chain-corruption.md)

---

### Issue 2: NAS VM Won't Boot After Reboot

**Symptoms:**
- NAS VM fails to start
- Error: "Cannot mount filesystem"
- /etc/fstab has errors

**Cause:**
Using /dev/sdX device names instead of UUIDs in /etc/fstab. Disk initialization order changed.

**Solution:**
Use UUID-based mounting. Always test with `findmnt --verify` before rebooting.

**Detailed Reference:** [03-disk-race-condition-disaster.md](../../troubleshooting/storage/03-disk-race-condition-disaster.md)

**Prevention:**
```bash
# ALWAYS use UUIDs in /etc/fstab
UUID=a1b2c3d4-e5f6-7890-abcd-ef1234567890  /mnt/shared_storage  ext4  defaults  0 0

# NEVER use device names
# /dev/sdb  /mnt/shared_storage  ext4  defaults  0 0  ← WRONG!
```

---

### Issue 3: Datastore Fills Up After Snapshot

**Symptoms:**
- Snapshot creates 900GB file instead of expected 50GB
- Datastore space exhaustion
- Cannot create more snapshots

**Cause:**
Thick provisioned disk or RAID-configured disk.

**Solution:**
Calculate 2x disk size before snapshot. Use Veeam for long-term backups instead.

**Detailed Reference:** [08-thick-provisioned-snapshot-size.md](../../troubleshooting/storage/08-thick-provisioned-snapshot-size.md)

**Space Calculation:**
```
Thick Disk: 905GB
Snapshot Required: 905GB × 1.5 = 1358GB
Datastore Capacity: 2TB Yes (sufficient)
```

---

### Issue 4: NAS VM Memory Starvation

**Symptoms:**
- Slow NFS performance
- High I/O wait times
- OOM (Out of Memory) errors in NAS VM logs

**Cause:**
Insufficient memory for NFS caching and concurrent backup operations.

**Solution:**
Increase NAS VM memory from 4GB to 8-9GB.

**Detailed Reference:** [05-nas-memory-starvation.md](../../troubleshooting/storage/05-nas-memory-starvation.md)

---

### Issue 5: NFS Mount Fails on ESXi

**Symptoms:**
- ESXi cannot mount NFS datastore
- Error: "Unable to mount NFS datastore"
- NAS VM network unreachable

**Troubleshooting Steps:**

**1. Check NFS Service:**
```bash
# On NAS VM
systemctl status nfs-server
sudo systemctl restart nfs-server
```

**2. Check NFS Exports:**
```bash
# On NAS VM
sudo exportfs -v
# Expected: /mnt/shared_storage and /mnt/datastor2 exported
```

**3. Check Firewall:**
```bash
# On NAS VM
sudo firewall-cmd --list-services
# Expected: nfs, rpc-bind, mountd

# If missing, add:
sudo firewall-cmd --permanent --add-service=nfs
sudo firewall-cmd --permanent --add-service=rpc-bind
sudo firewall-cmd --permanent --add-service=mountd
sudo firewall-cmd --reload
```

**4. Check Network Connectivity:**
```bash
# SSH to ESXi
vmkping 10.0.20.90
# Expected: < 1ms latency, 0% packet loss
```

**5. Check NFS Permissions:**
```bash
# On NAS VM
ls -ld /mnt/shared_storage
# Expected: drwxr-xr-x root root

# If incorrect:
sudo chmod 755 /mnt/shared_storage
sudo chown root:root /mnt/shared_storage
```

---

### Issue 6: Datastore Over-Provisioning

**Symptoms:**
- Datastore shows more allocated space than capacity
- VMs fail to start due to "insufficient space"
- Thin provisioning ratio > 3.0x

**Cause:**
Too many thin provisioned VMs on same datastore without monitoring.

**Solution:**
```bash
# Check thin provisioning ratio
# SSH to ESXi
df -h /vmfs/volumes/datastore

# Expected ratio: < 2.5x
# If > 3.0x: Migrate VMs or expand datastore
```

**Prevention:**
- Monitor datastore usage weekly
- Set vCenter alarms at 70% and 85%
- Plan for 2.0-2.5x max over-provisioning

---

### Issue 7: Snapshot Consolidation Fails

**Symptoms:**
- Snapshot deletion hangs
- Error: "Unable to access file since it is locked"
- Snapshot chain remains after deletion attempt

**Troubleshooting Steps:**

**1. Check for VM Locks:**
```bash
# SSH to ESXi
cd /vmfs/volumes/datastore/VM_folder/
ls -lh *.lck

# If locks exist, identify process:
ps | grep vmx
```

**2. Gracefully Release Lock:**
```bash
# Power off VM (if possible)
vim-cmd vmsvc/power.off <vmid>

# Delete snapshot
vim-cmd vmsvc/snapshot.remove <vmid> <snapshotId>

# Power on VM
vim-cmd vmsvc/power.on <vmid>
```

**3. Force Unlock (Last Resort):**
```bash
# DANGEROUS: Only if graceful methods fail
rm -rf /vmfs/volumes/datastore/VM_folder/*.lck
```

---

## Quick Diagnostic Commands

### ESXi Storage Health

```bash
# List all datastores
esxcli storage filesystem list

# Check NFS mounts
esxcli storage nfs list

# Check VMFS volumes
esxcli storage vmfs extent list

# Check disk health
esxcli storage core device list
```

### NAS VM Health

```bash
# Disk usage
df -h

# Disk I/O performance
iostat -x 5

# NFS exports status
sudo exportfs -v

# NFS service status
systemctl status nfs-server

# Network bonding status
cat /proc/net/bonding/bond0

# Memory usage
free -h

# Check fstab validity
sudo findmnt --verify
```

---

## Emergency Recovery Procedures

### Procedure 1: NFS Datastore Unavailable

**Immediate Actions:**
1. Check NAS VM is running
2. Verify NFS service: `systemctl status nfs-server`
3. Check network connectivity: `vmkping 10.0.20.90`
4. Restart NFS service: `sudo systemctl restart nfs-server`
5. Rescan datastores on ESXi: `esxcli storage core adapter rescan --all`

### Procedure 2: Datastore Out of Space

**Immediate Actions:**
1. Identify space consumers: `du -sh /vmfs/volumes/datastore/*`
2. Delete old snapshots: vCenter > VM > Snapshots > Delete All
3. Clean up ISO files and templates
4. Consider emergency VM migration to another datastore
5. Expand datastore if possible

### Procedure 3: NAS VM Disk Mount Failure

**Immediate Actions:**
1. Boot NAS VM into recovery mode
2. Check /etc/fstab for errors
3. Verify disk UUIDs: `blkid`
4. Fix fstab with correct UUIDs
5. Test mount: `sudo mount -a`
6. Reboot NAS VM

---

## Related Documentation

- [NAS Configuration](03-NAS-Configuration.md)
- [Snapshot Management](05-Snapshot-Management.md)
- [Performance Monitoring](06-Performance-Monitoring.md)
- [Troubleshooting Cases Directory](../../troubleshooting/storage/)
