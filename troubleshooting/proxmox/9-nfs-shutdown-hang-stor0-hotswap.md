# TS-PVE-009 | 2026-03-23 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Proxmox VE / NFS / USB-Ethernet
Sub-techs: stor0 adapter, NFS mounts, systemd shutdown
Environment: pve-dev (applicable to any Proxmox host with NFS over USB-Ethernet)
Re-opened: No

_____________________________________________________________________

[Issue Description]
System hangs on shutdown/reboot during USB-Ethernet adapter hot-swap for stor0 (storage network). Console shows no activity for several minutes, had to use the power button for a hard reboot.

_____________________________________________________________________

[Analysis]
# Step 1: Timeline from logs
```
18:03:10  stor0: unregister 'cdc_ncm'     <- Adapter unplugged
18:03:15  Interface "stor0" disabled       <- Network lost
18:06:41  Shutdown sequence started        <- Reboot command
18:07:01  nfs: server not responding       <- NFS timeout begins
18:07:59  umount.nfs4: device is busy      <- Can't unmount
18:09:15  Killing showmount with SIGKILL   <- Force kill
18:09:16  Reached shutdown target          <- Finally proceeds
```

# Step 2: Trace the hang
1. stor0 unplugged -- NFS mounts lose connectivity to NAS
2. Reboot initiated -- systemd tries graceful NFS unmount
3. NFS mount is `hard` -- waits indefinitely for server response
4. `timeo=600` -- 60-second timeout per retry
5. Device busy -- process still using mount, can't unmount
6. Shutdown stuck -- waiting for NFS cleanup

# Step 3: Check NFS mount options
```
hard              <- Retry forever (vs soft which gives up)
timeo=600         <- 60-second timeout per attempt
retrans=2         <- 2 retries before timeout message
```

_____________________________________________________________________

[Final Root Cause]
USB-Ethernet adapter unplugged while NFS mounts were active. NFS hard mounts wait indefinitely for server response, causing shutdown to hang while waiting for graceful unmount.

_____________________________________________________________________

[Final Solution]
Lazy unmount NFS before unplugging adapter. I now follow this procedure:

Before unplugging stor0:
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

Full hot-swap procedure for stor0 replacement:
```bash
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

Recovery if already stuck on shutdown:

Option 1: Wait 5-10 minutes for timeout (watchdog at 10min will force reboot if needed).

Option 2: Force reboot via command:
```bash
systemctl reboot --force --force
# Or kernel-level emergency reboot
echo b > /proc/sysrq-trigger
```

Option 3: Hold power button for 5-10 seconds.

After any force reboot:
```bash
ip link show stor0
mount | grep nfs
# If NFS not mounted:
pvesm status
systemctl restart pvedaemon pvestatd
```

Verified: Yes -- clean shutdown when proper procedure followed.

_____________________________________________________________________

[Risk Level] LOW -- VMs/LXCs lose NAS access during unmount, but recover after reboot.

_____________________________________________________________________

[References]
- USB-Ethernet Adapter Replacement Guide: `proxmox/disaster_recovery/hardware/usb-ethernet-adapter-replacement.md`
- Related: TS-PVE-004 (LXC snapshot NFS mount) -- NFS mount limitations
