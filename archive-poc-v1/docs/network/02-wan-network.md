# WAN/External Network

> **Bridge to home network for internet access and external management**

---

## Purpose

- Bridge to home router for internet access
- External management access
- Future VPN endpoint for hybrid cloud

---

## Network Configuration

**Subnet**: 192.x.x.x/24
**Gateway**: 192.x.x.1 (Home Router)
**VMware Type**: VMnet0 (Bridged to physical adapter)

---

## ESXi Master - vSwitch0

### vSwitch Configuration

**Uplinks**: 1 physical vNIC from VMnet0
**Security Policies:**
- Promiscuous Mode: OFF (not needed for bridged network)
- Forged Transmits: OFF
- MAC Changes: OFF

### Portgroups

#### 1. VM Network
- **Purpose**: VM connections to WAN
- **VMs**:
  - pfSense WAN interface: 192.x.x.##
  - vCenter WAN interface: 192.x.x.##

#### 2. Management Network
- **Purpose**: External ESXi management (backup access path)
- **Interface**: ESXi Master vmk0: 192.x.x.##

---

## Connected VMs

### pfSense WAN Interface
- **IP**: 192.x.x.##
- **Purpose**: Gateway to internet
- **Function**: NAT gateway for entire internal network

### vCenter Server (Dual-Homed)
- **WAN IP**: 192.x.x.##
- **LAN IP**: 10.0.20.89
- **Purpose**: Redundant access (both WAN and LAN)
- **Benefit**: Management access even if internal network fails

---

## Security Configuration

### Firewall Rules

**Web UI Access Restriction:**
- pfSense web UI accessible ONLY from authorized Mac PC IP (192.x.x.##)
- Windows Host not explicitly allowed on WAN (security by default)
- All inbound access denied by default

**Rationale:**
- Limits attack surface
- Prevents unauthorized configuration changes
- Security through network-level access control

### Future VPN Configuration

**Planned Use Case: AWS Site-to-Site VPN**
```
pfSense WAN (192.x.x.##)
  ↓
AWS Virtual Private Gateway
  ↓
AWS VPC (10.0.100.0/16)
```

**Benefits:**
- Secure hybrid cloud connectivity
- Private routing between on-prem and AWS
- No public internet exposure for sensitive traffic

---

## Why Bridged Mode?

**VMnet0 Bridged Advantages:**
- Direct access to home router
- Same subnet as physical workstations
- Simplifies home network integration
- No additional NAT layer

**Alternative Considered: NAT Mode**
- Additional NAT layer (complexity)
- Port forwarding required for external access
- More difficult VPN configuration

---

## Troubleshooting

### Issue: Cannot Access pfSense Web UI from Windows Host

**Symptom**: pfSense web UI unreachable from Windows laptop on WAN network

**Cause**: Firewall rule restricts access to Mac PC only

**Solution**: Access pfSense via LAN interface (10.0.20.170) from Windows Host instead of WAN interface

**Proper Access Methods:**
- Mac PC: Access via WAN (192.x.x.##) Yes
- Windows Host: Access via LAN (10.0.20.170) Yes

### Issue: VMs Cannot Access Internet

**Symptom**: VMs on internal network (10.0.20.x) cannot reach internet

**Cause**: pfSense NAT not configured or pfSense WAN interface down

**Verification:**
```bash
# SSH to pfSense (Option 8: Shell)
ping -c 3 8.8.8.8

# Expected: Successful ping
# If fails: Check home router connectivity
```

**Solution:**
1. Verify pfSense WAN interface has valid IP
2. Check NAT configuration: Firewall → NAT → Outbound
3. Verify outbound rule exists for 10.0.20.0/24

---

## Related Documentation

- [Network Overview](01-Network-Overview.md)
- [Internal Network](03-Internal-Network.md)
- [pfSense Configuration](05-pfSense-Configuration.md)
- [Network Security](07-Network-Security-and-Troubleshooting.md)
