# Troubleshooting: NFS Shutdown Hang During stor0 Hot-Swap

**Date**: 2026-03-23
**Affected**: pve-dev (applicable to any Proxmox host with NFS storage over USB-Ethernet)
**Resolution**: Lazy unmount NFS before unplugging storage network adapter

---

## Symptoms

During USB-Ethernet adapter hot-swap for stor0 (storage network):
- System hangs on shutdown/reboot
- Console shows no activity for several minutes
- Forced to use power button for hard reboot

---

## Root Cause Analysis

### Timeline from Logs

```
18:03:10  stor0: unregister 'cdc_ncm'     ← Adapter unplugged
18:03:15  Interface "stor0" disabled       ← Network lost
18:06:41  Shutdown sequence started        ← Reboot command
18:07:01  nfs: server not responding       ← NFS timeout begins
18:07:59  umount.nfs4: device is busy      ← Can't unmount
18:09:15  Killing showmount with SIGKILL   ← Force kill
18:09:16  Reached shutdown target          ← Finally proceeds
```

### The Problem

1. **stor0 unplugged** → NFS mounts lose connectivity to NAS
2. **Reboot initiated** → systemd tries graceful NFS unmount
3. **NFS mount is `hard`** → waits indefinitely for server response
4. **timeo=600** → 60-second timeout per retry
5. **Device busy** → process still using mount, can't unmount
6. **Shutdown stuck** → waiting for NFS cleanup

### NFS Mount Options (from mount output)

```
hard              ← Retry forever (vs soft which gives up)
timeo=600         ← 60-second timeout per attempt
retrans=2         ← 2 retries before timeout message
```

---

## Investigation Commands

```bash
# Check previous boot logs
journalctl --list-boots
journalctl -b -1 | grep -iE "nfs|mount|stor0|timeout|busy"

# Check current NFS mount options
mount | grep nfs

# Check what's using NFS mount
lsof +D /mnt/pve/nas-dev-data
fuser -m /mnt/pve/nas-dev-data
```

---

## Prevention

### Before Unplugging stor0

```bash
# 1. Check running VMs/LXCs (they may use NAS storage)
qm list | grep running
pct list | grep running

# 2. Stop VMs/LXCs using NAS storage, OR accept they'll lose NAS access temporarily

# 3. Lazy unmount all NFS mounts (detaches immediately, cleans up when idle)
umount -l /mnt/pve/nas-dev-data
umount -l /mnt/pve/nas-iso
umount -l /mnt/pve/nas-backups

# 4. Verify unmounts
mount | grep nfs  # Should be empty

# 5. Now safe to unplug stor0 adapter
```

### Proper Hot-Swap Procedure

```bash
# Full safe procedure for stor0 replacement:

# Step 1: Unmount NFS
umount -l /mnt/pve/nas-dev-data
umount -l /mnt/pve/nas-iso
umount -l /mnt/pve/nas-backups

# Step 2: Plug in new adapter (keep old connected)
ip link show | grep enx  # Get new MAC

# Step 3: Update .link file
nano /usr/local/lib/systemd/network/50-pmx-stor0.link

# Step 4: Unplug old adapter

# Step 5: Reload and reboot
systemctl daemon-reload && reboot

# Step 6: After reboot, NFS auto-remounts via Proxmox storage.cfg
mount | grep nfs
ping 10.0.40.120
```

---

## Recovery

### If Already Stuck on Shutdown

**Option 1: Wait** (may take 5-10 minutes)
- System will eventually timeout and proceed
- Watchdog timer (10min) will force reboot if needed

**Option 2: Force Reboot via Command**
```bash
# Force immediate reboot (skips service shutdown)
systemctl reboot --force --force

# Or kernel-level emergency reboot
echo b > /proc/sysrq-trigger
```

**Option 3: Power Button**
- Hold power button for 5-10 seconds
- Use if commands don't respond

After any force reboot, system recovers normally. NFS will reconnect once stor0 is configured.

### After Force Reboot

```bash
# 1. Verify stor0 is up with new MAC
ip link show stor0

# 2. Check NFS remounted
mount | grep nfs

# 3. If NFS not mounted, trigger remount
pvesm status  # Shows storage status
# Or restart PVE services
systemctl restart pvedaemon pvestatd
```

---

## Alternative: Soft NFS Mounts

To avoid future hangs, consider soft mounts (trade-off: may cause I/O errors):

```bash
# In Proxmox UI: Datacenter → Storage → NAS storage → Edit
# Add mount options: soft,timeo=50,retrans=3

# Or via CLI, edit /etc/pve/storage.cfg
# Add: options soft,timeo=50,retrans=3
```

| Mount Type | Behavior | Risk |
|------------|----------|------|
| **hard** (default) | Retry forever | Hangs on network loss |
| **soft** | Give up after timeout | I/O errors if NAS temporarily unavailable |

For hot-swap scenarios, lazy unmount is safer than changing to soft mounts.

---

## Related

- [USB-Ethernet Adapter Replacement Guide](../../proxmox/disaster_recovery/hardware/usb-ethernet-adapter-replacement.md)
- [Case 16: LXC Snapshot NFS Mount](16-proxmox-lxc-snapshot-nfs-mount.md) - NFS mount limitations

---

## Status

RESOLVED - Documented prevention procedure for future hot-swaps
