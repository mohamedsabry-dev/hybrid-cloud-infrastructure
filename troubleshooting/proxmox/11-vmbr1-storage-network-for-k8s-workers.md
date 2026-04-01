# TS-58: Storage Network (VLAN 40) for K8s Workers

## Problem Statement
K8s workers need direct access to NAS (10.0.40.x) for NFS-based Persistent Volumes.
The storage network (VLAN 40) was only accessible by Proxmox host via `stor0.40` interface.
VMs had no bridge to reach VLAN 40.

## Environment
- Proxmox: pve-dev
- K8s Workers: 1020, 1021, 1022
- Storage Network: VLAN 40 (10.0.40.0/24)
- NAS: 10.0.40.120

## Root Cause Analysis

### Initial State
```
Physical NIC: stor0
    |
VLAN Interface: stor0.40 (10.0.40.110)
    |
Proxmox Host Only (no VM access)
```

VMs couldn't reach VLAN 40 because there was no bridge for them to connect to.

### Failed Attempts via Proxmox Web GUI

**Attempt 1: Create vmbr1 with bridge-ports=stor0**
```
Error: "iface stor0 - ip address can't be set on interface if bridged"
```
Reason: stor0.40 (VLAN subinterface) existed with an IP. Linux doesn't allow bridging
a physical interface that has VLAN subinterfaces with IPs assigned.

**Attempt 2: Create vmbr1 with bridge-ports=stor0.40**
```
Error: "iface stor0.40 - ip address can't be set on interface if bridged"
```
Reason: stor0.40 had IP 10.0.40.110 assigned. You cannot bridge an interface
that has an IP address directly. The bridge (or VLAN interface on it) should hold the IP.

### Why Web GUI Failed
The Proxmox web GUI validates each change individually against the current running state.
It cannot perform atomic multi-interface restructuring:
1. Remove stor0.40 IP
2. Create bridge
3. Add IP to bridge

These must all happen together, which requires editing `/etc/network/interfaces` directly.

## Solution

### Step 1: Edit /etc/network/interfaces

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

### Step 2: Apply Network Changes
```bash
ifreload -a; sleep 20; systemctl restart networking
```

**IMPORTANT:** `ifreload -a` alone may cause network outage when restructuring
bridges. The `sleep 20; systemctl restart networking` acts as a failsafe.
If SSH disconnects, wait 20 seconds and reconnect - the restart will restore connectivity.

### Step 3: Verify
```bash
bridge vlan show
ip addr show vmbr1.40
ping 10.0.40.120  # NAS
```

## New Architecture
```
Physical NIC: stor0
    |
Bridge: vmbr1 (VLAN-aware, bridge-vids 40)
    |
    +--- vmbr1.40 (10.0.40.110) - Proxmox host NAS access
    |
    +--- VM NICs (tag=40) - VM access to VLAN 40
```

## VM Configuration

### Via Proxmox GUI
Hardware -> Add -> Network Device
- Bridge: vmbr1
- VLAN Tag: 40

### Via Terraform
```hcl
network_device {
  bridge  = "vmbr1"
  model   = "virtio"
  vlan_id = 40
}
```

## IP Assignments
| Node | Primary NIC (VLAN 64) | Storage NIC (VLAN 40) |
|------|----------------------|----------------------|
| k8s-worker1 | 10.0.64.10 | 10.0.40.201 |
| k8s-worker2 | 10.0.64.11 | 10.0.40.202 |
| k8s-worker3 | 10.0.64.12 | 10.0.40.203 |

## Verification Commands

On Proxmox:
```bash
bridge vlan show
```

On K8s workers:
```bash
ip a | grep -A3 ens19
ping 10.0.40.120  # NAS
```

## Known Issues

### ifreload -a Network Outage
When restructuring bridges (moving interfaces from VLAN to bridge), `ifreload -a`
may cause temporary network outage that doesn't self-recover.

**Symptom:** SSH disconnects after running `ifreload -a`, cannot reconnect.

**Root Cause:** Bridge port transitions can leave network in inconsistent state.

**Solution:** Always use the failsafe command:
```bash
ifreload -a; sleep 20; systemctl restart networking
```

The `systemctl restart networking` after 20 seconds restores connectivity
even if `ifreload -a` caused an outage.

### wpasupplicant Error During Restart
When running `systemctl restart networking`, you may see:
```
error: wlp1s0: pre-up cmd '/etc/network/if-pre-up.d/wpasupplicant' failed: returned 1
```

**Symptom:** Error message about WiFi interface during network restart.

**Root Cause:** wpasupplicant script doesn't handle restart gracefully when already connected.

**Impact:** Usually harmless - WiFi typically reconnects anyway. Non-critical if
you have alternative access (console, other network).

## Lessons Learned
1. Proxmox web GUI cannot do atomic network restructuring
2. VLAN interfaces with IPs cannot be used as bridge ports
3. Solution: Bridge the physical NIC, use VLAN interface on the bridge for host IP
4. Always backup `/etc/network/interfaces` before changes
5. Have console/WiFi access as fallback when modifying network
6. Use `ifreload -a; sleep 20; systemctl restart networking` for bridge changes

## Related Files
- `/etc/network/interfaces` - Proxmox network config
- `proxmox/bootstrap_proxmox/network-setup.sh` - Bootstrap script (updated)
- `proxmox/bootstrap_proxmox/vmbr1-vlan40-setup.txt` - Detailed documentation

## Date
2026-03-27
