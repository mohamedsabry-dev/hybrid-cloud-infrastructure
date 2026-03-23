# USB-Ethernet Adapter Replacement Guide

When a USB-Ethernet adapter fails, replace it and update the MAC address mapping.

> **Background**: This DR preparation was created after experiencing an outage due to hardware issues.
> See: [TS Case 43: Switch Port 4 Link Flapping](/troubleshooting/network/43-switch-port4-link-flapping-loose-connection.md)

---

## How It Works

Proxmox uses systemd `.link` files to map MAC addresses to interface names:

```
/usr/local/lib/systemd/network/50-pmx-svc0.link
/usr/local/lib/systemd/network/50-pmx-stor0.link
```

Each file simply matches MAC → Name:
```ini
[Match]
MACAddress=XX:XX:XX:XX:XX:XX
Type=ether

[Link]
Name=svc0
```

---

## Current Adapter MACs (Update This)

### pve-dev
| Interface | MAC Address | Adapter |
|-----------|-------------|---------|
| svc0 | `**:**:**:**:**:b2` | ASIX AX88179B (USB-C to ETH) |
| stor0 | `**:**:**:**:**:fd` | ASIX AX88179B (USB-C to ETH) |
| wifi0 | `XX:XX:XX:XX:XX:XX` | |

> **Note**: Old MACs commented out in `.link` files for reference:
> - svc0: `**:**:**:**:**:ad`
> - stor0: `**:**:**:**:**:3e`

### pve-prod
| Interface | MAC Address | Adapter |
|-----------|-------------|---------|
| svc0 | `XX:XX:XX:XX:XX:XX` | |
| stor0 | `XX:XX:XX:XX:XX:XX` | |
| wifi0 | `XX:XX:XX:XX:XX:XX` | |

> **Note**: Run `cat /usr/local/lib/systemd/network/*.link` on each host to get actual MACs.

---

## Replacement Steps

> **WARNING: stor0 Replacement**
>
> If replacing stor0 (storage network), unmount NFS **before** unplugging to avoid shutdown hang.
> See: [TS Case 55: NFS Shutdown Hang](/troubleshooting/proxmox/55-nfs-shutdown-hang-stor0-hotswap.md)
>
> ```bash
> umount -l /mnt/pve/nas-dev-data
> umount -l /mnt/pve/nas-iso
> umount -l /mnt/pve/nas-backups
> ```

### 1. Plug in new adapter

### 2. Find its MAC address

```bash
# New adapter will have a name like enxXXXXXX
ip link show

# Get its MAC
ip link show enx* 2>/dev/null || ip link show eth* 2>/dev/null
```

### 3. Update the .link file

```bash
# For svc0:
nano /usr/local/lib/systemd/network/50-pmx-svc0.link

# For stor0:
nano /usr/local/lib/systemd/network/50-pmx-stor0.link
```

Change the `MACAddress=` line to the new MAC.

### 4. Apply changes

```bash
# Reload systemd
systemctl daemon-reload
udevadm control --reload-rules

# Reboot (cleanest way)
reboot
```

### 5. Verify

```bash
ip link show svc0
ip link show stor0
ping 10.0.40.120  # storage network test
```

---

## Quick Reference Commands

```bash
# Show current link files
cat /usr/local/lib/systemd/network/*.link

# Find all network interfaces with MACs
ip -o link show | awk '{print $2, $(NF-2)}'

# Check which adapter is which
udevadm info /sys/class/net/svc0 | grep -E "ID_MODEL|ID_SERIAL|MAC"
```

---

## Backup Adapters

Keep spare adapters and **pre-document their MACs**:

| Spare # | MAC Address | Model | Type | Notes |
|---------|-------------|-------|------|-------|
| 1 | `**:**:**:**:**:ad` | ASIX AX88179B | USB-C to ETH | Former pve-dev svc0 |
| 2 | `**:**:**:**:**:3e` | ASIX AX88179B | USB-C to ETH | Former pve-dev stor0 |

When a failure occurs, just update the .link file with the spare's MAC.

---

## Emergency Recovery (Adapter Already Failed)

If stor0 fails unexpectedly (not planned swap), NFS is already unreachable. You **cannot** cleanly unmount.

### Procedure

```bash
# 1. Plug in replacement adapter
ip link show | grep enx   # Get new MAC

# 2. Update .link file with new MAC
nano /usr/local/lib/systemd/network/50-pmx-stor0.link

# 3. Force reboot (graceful reboot will hang on NFS)
systemctl reboot --force --force
# Or if that doesn't work:
echo b > /proc/sysrq-trigger
# Last resort: hold power button 5-10 seconds
```

### Why Force Reboot?

| Scenario | `reboot` behavior |
|----------|-------------------|
| NFS reachable | Clean unmount, clean shutdown |
| NFS unreachable | Waits 60s+ per mount, hangs |
| After force reboot | System recovers, NFS remounts automatically |

### After Recovery

```bash
# Verify stor0 is up
ip link show stor0

# Verify NFS remounted
mount | grep nfs

# If NFS not mounted, trigger remount
systemctl restart pvedaemon pvestatd
```

---

## Related

- [TS Case 55: NFS Shutdown Hang During stor0 Hot-Swap](/troubleshooting/proxmox/55-nfs-shutdown-hang-stor0-hotswap.md)
