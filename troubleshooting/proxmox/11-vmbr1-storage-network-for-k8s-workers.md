# TS-PVE-011 | 2026-03-27 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Proxmox VE network configuration
Sub-techs: stor0, vmbr1, VLAN 40, K8s workers, NAS
Environment: pve-dev
Re-opened: No

_____________________________________________________________________

[Issue Description]
K8s workers needed direct access to NAS (10.0.40.x) for NFS-based Persistent Volumes. Storage network (VLAN 40) was only accessible by the Proxmox host via `stor0.40` interface -- VMs had no bridge to reach VLAN 40.

Errors when I tried to create vmbr1 via Proxmox Web GUI:
```
Attempt 1: Create vmbr1 with bridge-ports=stor0
Error: "iface stor0 - ip address can't be set on interface if bridged"

Attempt 2: Create vmbr1 with bridge-ports=stor0.40
Error: "iface stor0.40 - ip address can't be set on interface if bridged"
```

Affected systems: K8s Workers 1020, 1021, 1022 -- Storage Network VLAN 40 (10.0.40.0/24) -- NAS at 10.0.40.120.

_____________________________________________________________________

[Analysis]
# Step 1: Understand initial state
```
Physical NIC: stor0
    |
VLAN Interface: stor0.40 (10.0.40.110)
    |
Proxmox Host Only (no VM access)
```

# Step 2: Why Web GUI failed
Attempt 1: stor0.40 (VLAN subinterface) existed with an IP. Linux doesn't allow bridging a physical interface that has VLAN subinterfaces with IPs assigned.

Attempt 2: stor0.40 had IP 10.0.40.110 assigned. You cannot bridge an interface that has an IP address directly -- the bridge (or VLAN interface on it) should hold the IP.

The Proxmox web GUI validates each change individually against current running state. It cannot perform atomic multi-interface restructuring -- these must all happen together via `/etc/network/interfaces`.

_____________________________________________________________________

[Final Root Cause]
Proxmox Web GUI cannot perform atomic network restructuring. VLAN interfaces with IPs cannot be used as bridge ports directly. Manual edit of `/etc/network/interfaces` required.

_____________________________________________________________________

[Final Solution]
I edited `/etc/network/interfaces` directly to create a VLAN-aware bridge.

Step 1: Edit /etc/network/interfaces

Changed from:
```
auto stor0
iface stor0 inet manual

auto stor0.40
iface stor0.40 inet static
    address 10.0.40.110
    netmask 255.255.255.0
    vlan-raw-device stor0
```

To:
```
auto stor0
iface stor0 inet manual

auto vmbr1
iface vmbr1 inet manual
    bridge-ports stor0
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 40

auto vmbr1.40
iface vmbr1.40 inet static
    address 10.0.40.110
    netmask 255.255.255.0
```

Step 2: Apply network changes
```bash
ifreload -a; sleep 20; systemctl restart networking
```
IMPORTANT: `ifreload -a` alone may cause network outage when restructuring bridges. The `sleep 20; systemctl restart networking` acts as a failsafe.

Step 3: Verify
```bash
bridge vlan show
ip addr show vmbr1.40
ping 10.0.40.120  # NAS
```

New architecture:
```
Physical NIC: stor0
    |
Bridge: vmbr1 (VLAN-aware, bridge-vids 40)
    |
    +--- vmbr1.40 (10.0.40.110) - Proxmox host NAS access
    |
    +--- VM NICs (tag=40) - VM access to VLAN 40
```

IP assignments:
| Node | Primary NIC (VLAN 64) | Storage NIC (VLAN 40) |
|------|----------------------|----------------------|
| k8s-worker1 | 10.0.64.10 | 10.0.40.201 |
| k8s-worker2 | 10.0.64.11 | 10.0.40.202 |
| k8s-worker3 | 10.0.64.12 | 10.0.40.203 |

VM configuration (via Proxmox GUI): Hardware -> Add -> Network Device, Bridge: vmbr1, VLAN Tag: 40.

Via Terraform:
```hcl
network_device {
  bridge  = "vmbr1"
  model   = "virtio"
  vlan_id = 40
}
```

Known issue -- wpasupplicant error during ifreload:
```
error: wlp1s0: pre-up cmd '/etc/network/if-pre-up.d/wpasupplicant' failed: returned 1
```
Usually harmless -- WiFi typically reconnects anyway.

Verified: Yes -- VMs connect to VLAN 40 via vmbr1, Proxmox host retains NAS access via vmbr1.40, K8s workers can mount NFS PVs directly.

_____________________________________________________________________

[Risk Level] MEDIUM -- network outage during bridge restructuring. Always have console/WiFi access as fallback.

_____________________________________________________________________

[References]
- `/etc/network/interfaces` -- Proxmox network config
- `proxmox/bootstrap_proxmox/network-setup.sh` -- Bootstrap script
- `proxmox/bootstrap_proxmox/vmbr1-vlan40-setup.txt` -- Detailed documentation
