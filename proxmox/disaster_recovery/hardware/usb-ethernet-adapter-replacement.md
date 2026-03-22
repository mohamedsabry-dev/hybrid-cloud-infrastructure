# USB-Ethernet Adapter Replacement Guide

When a USB-Ethernet adapter fails, replace it and update the MAC address mapping.

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
| svc0 | `XX:XX:XX:XX:XX:XX` | ASIX AX88179B |
| stor0 | `XX:XX:XX:XX:XX:XX` | |
| wifi0 | `XX:XX:XX:XX:XX:XX` | |

### pve-prod
| Interface | MAC Address | Adapter |
|-----------|-------------|---------|
| svc0 | `XX:XX:XX:XX:XX:XX` | |
| stor0 | `XX:XX:XX:XX:XX:XX` | |
| wifi0 | `XX:XX:XX:XX:XX:XX` | |

> **Note**: Run `cat /usr/local/lib/systemd/network/*.link` on each host to get actual MACs.

---

## Replacement Steps

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

| Spare # | MAC Address | Model |
|---------|-------------|-------|
| 1 | | |
| 2 | | |

When a failure occurs, just update the .link file with the spare's MAC.
